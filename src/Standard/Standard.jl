module Standard

	using Roots, Optim

	import ..Models:
		    Param, 
		    Model, 
		    iidModel, 
		    iidDebtModel, 
		    AR1Model, 
		    AR1Model_a,
		    linearapprox,u,up,iup

	export runStd,EGM!,Euler!,VFbi!

	include("solutions.jl")

end 