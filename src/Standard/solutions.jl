

function solve!(m::Model,p::Param)

	if m.solver == "EGM"
		EGM!(m,p)
	elseif m.solver == "VFbi"
		VFbi!(m,p)
	elseif m.solver == "Euler"
		Euler!(m,p)
	end
end

# run all
function runStd()

	# return a Dict of Dicts
	D = Dict{AbstractString,Any}()

	# iid model dict
	d = Dict{AbstractString,Model}()

	# iid income models

	p = Param(mu=10.0)

	# solve by standard euler equation root finding
	d["Euler"] = iidModel(p)
	# warm up the JIT
	Euler!(d["Euler"],p)
	# reset el
	d["Euler"] = iidModel(p)
	# measure time
	d["Euler"].toc = @elapsed Euler!(d["Euler"],p)



	# solve maximizing the value function backward iteration
	d["VF"] = iidModel(p)
	VFbi!(d["VF"],p)
	d["VF"] = iidModel(p)
	d["VF"].toc = @elapsed VFbi!(d["VF"],p)

	# solve by EGM
	d["EGM"] = iidModel(p)
	EGM!(d["EGM"],p)
	d["EGM"] = iidModel(p)
	d["EGM"].toc = @elapsed EGM!(d["EGM"],p)

	D["iid"] = d	

	# plot results
	# plots(EE,EGM,VF,p)

	# AR1 income model
	# ================

	# d2 = Dict{AbstractString,Model}()
	# p = Param(mu=10.0)

	# d2["EGM"] = AR1Model(p)
	# d2["EGM"].toc = @elapsed EGM!(d2["EGM"],p)

	# d2["VF"] = AR1Model(p)
	# d2["VF"].toc = @elapsed VFbi!(d2["VF"],p)

	# # does it matter whether I compute the model on 
	# # current assets, given y, or
	# # cash-on-hand, given y?
	# d2["VF_a"] = AR1Model_a(p)
	# d2["VF_a"].toc = @elapsed VFbi!(d2["VF_a"],p)

	# D["AR1"] = d2

	# # plot results
	# # plots(EGMmod,VFmod,VFmod_a,p,1)  # plot period 1


	# # with debt
	# d3 = Dict{String,Model}()
	# p = Param()
	# d3["EGM"] = iidDebtModel(p)
	# EGM!(d3["EGM"],p)

	# D["iidDebt"] = d3

	return D
end






# endogenous grid method
function EGM!(m::iidModel,p::Param)

	# final period: consume everything.
	m.M[:,p.nT] = m.avec
	m.C[:,p.nT] = m.avec
	m.C[m.C[:,p.nT].<p.cfloor,p.nT] = p.cfloor

	m.V[:,p.nT] = u(m.C[:,p.nT],p) + p.beta * 0.0

	# preceding periods
	for it in (p.nT-1):-1:1

		# interpolate optimal consumption from next period on all cash-on-hand states
		# using C[:,it+1] and M[:,it+1], find c(m,it)

		tmpx = [0.0; m.M[:,it+1] ] 
		tmpy = [0.0; m.C[:,it+1] ]
		for ia in 1:p.na
			for iy in 1:p.ny
				m.c1[ia+p.na*(iy-1)] = linearapprox(tmpx,tmpy,m.m1[ia+p.na*(iy-1)],1,p.na)
			end
		end

		# get expected marginal value of saving: RHS of euler equation
		# beta * R * E[ u'(c_{t+1}) ] 
		Eu = p.R * p.beta .* up(m.c1,p) * m.ywgt

		# get optimal consumption today from euler equation: invert marginal utility
		m.C[:,it] = iup(Eu,p)

		# floor consumption
		m.C[m.C[:,it].<p.cfloor,it] = p.cfloor


		# get endogenous grid today
		m.M[:,it] = m.C[:,it] .+ m.avec

		# compute value function
		# ======================

		# expected value function (na,ny)
		fill!(m.ev,NaN)
		# dont: don't interpolate anything.
		if it==(p.nT-1)
			dont = trues(size(m.m1))
		else
			dont = m.m1 .< m.M[1,it+1]	# wherever potential next period's cash on hand (m.m1) is less than the lowest grid point of the endogenous grid next period (m.M), the agent will be credit constrained and will be saving zero (m.EV[1,it+1])
		end

		vv = m.V[:,it+1]
		tmpx = m.M[:,it+1]  
		for ia in 1:p.na
			for iy in 1:p.ny
				idx = ia+p.na*(iy-1)
				if dont[idx]
					m.ev[idx] = u(m.m1[idx],p) + p.beta * m.Vzero[it+1]
				else
					m.ev[idx] = linearapprox(tmpx,vv,m.m1[idx],1,p.na)
				end
			end
		end
		ev = m.ev * m.ywgt
		# if abs(m.avec[1]) > 1e-6
		# 	error("first element of avec is assumed to be zero: it's not!")
		# end
		m.Vzero[it] = ev[1] # save expected value of saving zero in first element.
		m.V[:,it]  = u(m.C[:,it],p) + p.beta * ev 
	end
end



# endogenous grid method for AR1 model
function EGM!(m::AR1Model,p::Param)

	# final period: consume everything.
	m.M[:,:,p.nT] = repmat(m.avec,1,p.ny)
	m.C[:,:,p.nT] = repmat(m.avec,1,p.ny)
	cc = m.C[:,:,p.nT]
	cc[cc.<p.cfloor] = p.cfloor
	m.C[:,:,p.nT] = cc

	m.V[:,:,p.nT] = u(m.C[:,:,p.nT],p) + p.beta * 0.0

	# preceding periods
	for it in (p.nT-1):-1:1

		# conditional on current income state
		for iy in 1:p.ny

			# interpolate optimal consumption from next period on all cash-on-hand states
			# using C[:,it+1] and M[:,it+1], find c(m,it)

			# next period's income index
			for iiy in 1:p.ny
				tmpx = [0.0; m.M[:,iiy,it+1] ] 
				tmpy = [0.0; m.C[:,iiy,it+1] ]
				for ia in 1:p.na
					m.c1[ia+p.na*(iiy-1)] = linearapprox(tmpx,tmpy,m.m1[ia+p.na*(iiy-1)],1,p.na)
					# m.c1[ia+p.na*(iiy-1)] = linearapprox(tmpx,tmpy,m.m1[ia+p.na*(iy-1)],1,p.na)
				end
			end

			# get expected marginal value of saving: RHS of euler equation
			# beta * R * E[ u'(c_{t+1}) | y_t] 
			Eu = p.R * p.beta .* m.ywgt[iy,:] * transpose(up(m.c1,p))

			# get optimal consumption today from euler equation: invert marginal utility
			m.C[:,iy,it] = iup(Eu,p)
			
			# floor consumption
			m.C[m.C[:,iy,it].<p.cfloor,iy,it] = p.cfloor

			# get endogenous grid today
			m.M[:,iy,it] = m.C[:,iy,it] .+ m.avec


			# compute value function
			# ======================

			# expected value function (na,ny)
			fill!(m.ev,NaN)
			# dont: don't interpolate anything.
			if it==(p.nT-1)
				# if next period is final period, don't have to worry about
				# next (i.e. period T+1) savings
				dont = trues(size(m.m1))
			else
				dont = m.m1 .< m.M[1,iy,it+1]	# wherever potential next period's cash on hand (m.m1) is less than the lowest grid point of the endogenous grid next period (m.M), the agent will be credit constrained and will be saving zero (here stored in m.Vzero[iy,it+1])
			end

			# for next period's income state
			for iiy in 1:p.ny
				tmpx = m.M[:,iiy,it+1]  
				vv   = m.V[:,iiy,it+1]
				for ia in 1:p.na
					idx = ia+p.na*(iiy-1)
					# idx = ia+p.na*(iy-1)
					if dont[idx]
						m.ev[idx] = u(m.m1[idx],p) + p.beta * m.Vzero[iiy,it+1]
					else
						m.ev[idx] = linearapprox(tmpx,vv,m.m1[idx],1,p.na)
					end
				end
			end
			# ev = transpose(m.ywgt[iy,:] * transpose( m.ev ))
			ev = m.ev * m.ywgt[iy,:][:] 
			if abs(m.avec[1]) > 1e-6
				error("first element of avec is assumed to be zero: it's not!")
			end
			m.Vzero[iy,it] = ev[1] # save expected value of saving zero in first element.
			m.V[:,iy,it]  = u(m.C[:,iy,it],p) .+ p.beta * ev
		end  # current income
	end  # age
end


# endogenous grid method for negative borrowing constraint
function EGM!(m::iidDebtModel,p::Param)

	# final period: consume everything.

	it = p.nT
	set!(m.c[it],linspace(p.a_lowT,p.a_high,p.na))
	set!(m.m[it],linspace(p.a_lowT,p.a_high,p.na))
	set!(m.v[it],u(m.c[it],p))
	set_vbound!(m.v[it],0.0)

	# preceding periods
	for it in (p.nT-1):-1:1


		# interpolate optimal consumption from next period on all cash-on-hand states
		# using C[:,it+1] and M[:,it+1], find c(m,it)
		m1 = m.m1[:,:,it]

		tmpx = [m.bounds[it+1], m.M[:,it+1] ]   # m.bounds[it+1] is the borrowing limit at age it+1
		tmpy = [0.0, m.C[:,it+1] ]   # cons always bounded by zero
		for ia in 1:p.na
			for iy in 1:p.ny
				m.c1[ia+p.na*(iy-1)] = linearapprox(tmpx,tmpy,m1[ia+p.na*(iy-1)])
			end
		end

		# get expected marginal value of saving: RHS of euler equation
		# beta * R * E[ u'(c_{t+1}) ] 
		Eu = p.R * p.beta .* up(m.c1,p) * m.ywgt

		# get optimal consumption today from euler equation: invert marginal utility
		m.C[:,it] = iup(Eu,p)

		# floor consumption
		m.C[m.C[:,it].<p.cfloor,it] = p.cfloor


		# get endogenous grid today
		# consumption + end-of-period assets
		m.M[:,it] = m.C[:,it] .+ m.avec[:,it+1]

		# compute value function
		# ======================

		dont = m.dont[:,:,it]

		# expected value function (na,ny)
		fill!(m.ev,NaN)
		# dont: don't interpolate anything.
		if it==(p.nT-1)
			dont = trues((p.na,p.ny))
		else
			dont = m1 .< m.M[1,it+1]	# wherever potential next period's cash on hand (m.m1) is less than the lowest grid point of the endogenous grid next period (m.M), the agent will be credit constrained and will be saving zero (m.EV[1,it+1])
		end

		vv = m.V[:,it+1]
		tmpx = m.M[:,it+1]  
		for ia in 1:p.na
			for iy in 1:p.ny
				idx = ia+p.na*(iy-1)
				if dont[idx]
					m.ev[idx] = u(m.c1[idx],p) + p.beta * m.Vzero[it+1]		# CRUCIAL: use next period's consumption function! cannot just use m1 as was the case with a zero borrowing constraint! m1[1] could be a negative number here!
				else
					m.ev[idx] = linearapprox(tmpx,vv,m1[idx])
				end
			end
		end
		ev = m.ev * m.ywgt
		# if abs(m.avec[1]) > 1e-6
		# 	error("first element of avec is assumed to be zero: it's not!")
		# end
		m.Vzero[it] = ev[1] # save expected value of borrowing the maximal amount.
		m.V[:,it]  = u(m.C[:,it],p) + p.beta * ev 

		m.dont[:,:,it] = dont 

	end
end

# solving the euler equation
function Euler!(m::iidModel,p::Param)

	# final period: consume everything.
	m.M[:,p.nT] = m.avec 
	m.C[:,p.nT] = m.avec
	m.C[m.C[:,p.nT].<p.cfloor,p.nT] = p.cfloor
	m.V[:,p.nT] = u(m.C[:,p.nT],p) + p.beta * 0.0

	# preceding periods
	for it in (p.nT-1):-1:1

		for ia in 1:p.na

			cash = m.avec[ia] 	# current cash on hand

			# consumption equal to cash on hand
			res = EulerResid(cash,cash,m.C[:,it+1],p,m,it)

			# this is an implication of 
			# equation (6) in Deaton ECTA (1991):
			# u'(c_t) = max[ u'(m_t), beta * R * u'(c_{t+1}) ]
			# with constraint a_t >= 0, if
			# c_t = m_t => a_{t+1} = 0   (consume everything, possible constrained: wanted to consume more by borrowing, but could not.)
			# c_t < m_t => a_{t+1} > 0   (consume less than m and save some for tomorrow)
			# c_t > m_t => a_{t+1} < 0   (consume more than m by borrowing)
			# the residual function EulerResid returns
			# c - u'^(-1) [ beta * E[ u'(beta * R * E[ u'(c_{t+1}) ] )] ]
			# where c_{t+1} is implied by today's choice c.
			# if that difference is negative when c_t = m_t, this means that 
			# c_t < c_{t+1} or
			# u'(c_t) > u'(c_{t+1}), or (by c_t = m_t)
			# u'(m_t) > u'(c_{t+1}), and therefore
			# u'(c_t) = max[ u'(m_t), beta * R * u'(c_{t+1}) ] implies
			# that this consumer is borrowing constrained and consumes all cash in hand.
			if res < 0
				m.C[ia,it] = cash
			else
				# m.C[ia,it] = fzero((x)->EulerResid(x,cash,m.C[:,it+1],p,m,it),(cash + p.a_low-0.0001)/2,[p.a_low-0.0001,cash])
				# m.C[ia,it] = fzero((x)->EulerResid(x,cash,m.C[:,it+1],p,m,it),cash/2,[p.a_low,cash])
				m.C[ia,it] = fzero((x)->EulerResid(x,cash,m.C[:,it+1],p,m,it),[p.a_low,cash])
			end
			m.S[ia,it] = (cash - m.C[ia,it])*p.R

			# get expected value function
			EV = linearapprox(m.avec,m.V[:,it+1],m.S[ia,it].+ m.yvec)

			m.V[ia,it] = u(m.C[ia,it],p) + p.beta * dot(EV,m.ywgt)

		end
		ev



	end

end

# Euler Equation Residual
function EulerResid(c::Float64,cash::Float64,cplus::Vector{Float64},p::Param,m::iidModel,it::Int)

	# given current c, what is next period's cash on hand

	# if it == (p.nT-1)
	# 	# next period is last: no income!
	# 	Euc = p.R .* p.beta .* up(p.R * (cash - c),p)
	# else
		m.m2 = p.R * (cash - c) .+ m.yvec  # (ny,1)
		# interpolate optimal consumption c(t+1), given c(t), on each y-state
		m.c2 = linearapprox([0;m.avec],[0;cplus],m.m2)
		# for iy in 1:p.ny
		# 	# m.c2[iy] = linearapprox([0,m.avec],[0,cplus],m.m2[iy],1,p.na)
		# 	m.c2[iy] = linearapprox(m.avec,cplus,m.m2[iy])
		# end

		# Expected marginal utility of consumption (RHS of euler equation)
		Euc = dot(p.R .* p.beta .* up(m.c2,p), m.ywgt) 	# (1,1)
	# end

	# residual
	c - iup(Euc,p)

end



# finding the maximum of the value function backward iteration
function VFbi!(m::iidModel,p::Param)

	# final period: consume everything.
	m.C[:,p.nT] = m.avec
	m.C[m.C[:,p.nT].<p.cfloor,p.nT] = p.cfloor
	m.V[:,p.nT] = u(m.C[:,p.nT],p)

	# w = zeros(p.na)
	# v = 0.0
	# i = 0

	# preceding periods
	for it in (p.nT-1):-1:1

		for ia in 1:p.na

			cash = m.avec[ia] 	# current cash on hand

			# Brent's method for minimizing a function
			# withotu derivatives
			x = optimize((x)->VFobj(x,cash,m.V[:,it+1],m,p,m.ywgt,it),p.a_low-100*eps(),cash)
			m.V[ia,it] = -x.f_minimum
			m.C[ia,it] = x.minimum

			# alternative: grid search

			# cvals = collect(linspace(p.a_low,cash,p.na))
			# for iia in 1:p.na
			# 	w[iia] = VFobj(cvals[iia],cash,m.V[:,it+1],m,p,m.ywgt,it)
			# end
			# v,i = findmin(w)
			# m.V[ia,it] = -v
			# m.C[ia,it] = cvals[i]
		end
	end
end
function VFobj(c::Float64,cash::Float64,Vplus::Array{Float64},m::iidModel,p::Param,integw::Vector{Float64},it::Int)

	s = (cash - c) * p.R .+ m.yvec
	for iy in 1:p.ny
		m.m2[iy] = linearapprox(m.avec,Vplus,s[iy],1,p.na)
	end
	v = u(c,p) + p.beta * dot(m.m2,integw)
	return -v
end



# finding the maximum of the value function backward iteration
# AR1 model

function VFbi!(m::AR1Model,p::Param)

	# final period: consume everything.
	x = m.avec
	x[x.<p.cfloor] = p.cfloor
	m.C[:,:,p.nT] = repmat(x,1,p.ny)
	m.V[:,:,p.nT] = u(m.C[:,:,p.nT],p)

	# preceding periods
	for it in (p.nT-1):-1:1

		# compute conditional expected value function
		# m.EV[:,:,it] = transpose(m.ywgt * transpose(m.V[:,:,it+1]))

		# conditional on current income state
		for iy in 1:p.ny

			for ia in 1:p.na

				cash = m.avec[ia]  # take asset grid as current cash on hand (add random income to next period savings)

				# Brent's method for minimizing a function
				# without derivatives
				x = optimize((x)->VFobj(x,cash,m.V[:,:,it+1],m,p,m.ywgt[iy,:][:]),p.a_low-100*eps(),cash)
				m.V[ia,iy,it] = -x.f_minimum
				m.C[ia,iy,it] = x.minimum
			end
		end
	end
end
function VFobj(c::Float64,cash::Float64,Vplus::Matrix{Float64},m::AR1Model,p::Param,integw::Vector{Float64})

	# implied cash on hand tomorrow
	s = (cash - c) * p.R + m.yvec
	# integrate out tomorrow's income uncertainty
	for iy in 1:p.ny
		m.m2[iy] = linearapprox(m.avec,Vplus[:,iy],s[iy],1,p.na)
	end
	v = u(c,p) + p.beta * dot(m.m2,integw)

	return -v
end




function VFbi!(m::AR1Model_a,p::Param)

	# final period: consume everything.
	x = m.avec
	x[x.<p.cfloor] = p.cfloor
	m.C[:,:,p.nT] = repmat(x,1,p.ny)
	m.V[:,:,p.nT] = u(m.C[:,:,p.nT],p)

	# preceding periods
	for it in (p.nT-1):-1:1

		# conditional on current income state
		for iy in 1:p.ny

			# compute conditional expected value function
			m.EV =  m.V[:,:,it+1] * m.ywgt[iy,:][:]  # (na,ny) * (ny,1) = (na,	1)

			for ia in 1:p.na

				cash = m.avec[ia] + m.yvec[iy] # current cash on hand

				# Brent's method for minimizing a function
				# withotu derivatives
				x = optimize((x)->VFobj(x,cash,m,p),p.a_low-100*eps(),cash)
				m.V[ia,iy,it] = -x.f_minimum
				m.C[ia,iy,it] = x.minimum
			end
		end
	end
end
function VFobj(c::Float64,cash::Float64,m::AR1Model_a,p::Param)

	# implied savings tomorrow
	s = (cash - c) * p.R 
	# get the expected value function at savings s
	EV = linearapprox(m.avec,m.EV,s)
	v = u(c,p) + p.beta * EV
	return -v
end



