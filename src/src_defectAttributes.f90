!*****************************************************************************************
!>double precision function findDiffusivity(matNum, defectType):
!returns the diffusivity of a given defect type
!*****************************************************************************************
double precision function findDiffusivity(matNum, defectType)
	use mod_structures
	use mod_constants
	implicit none

	integer defectType(numSpecies)
	integer i, j, numSame, matNum
	double precision Diff
	double precision DiffusivityCompute, diffusivityCu

	!Temporary: used as a parameter to vary the diffusivity of all defects on GB
	double precision, parameter :: Param=0d0

	outer1: do i=1,numSingleDiff(matNum)
		numSame=0
		do j=1,numSpecies
			if(defectType(j)==DiffSingle(i,matNum)%defectType(j)) then
				numSame=numSame+1
			end if
		end do

		if (numSame==numSpecies) then
			if(matNum==2) then
				if(DefectType(1)==1 .AND. DefectType(2)==0 .AND. DefectType(3)==0 .AND. DefectType(4)==0) then
					Diff=diffusivityCu(matNum)
					exit outer1
				else
					Diff=DiffSingle(i,matNum)%D*dexp(-(DiffSingle(i,matNum)%Em-Param)/(kboltzmann*temperature))
					exit outer1
				end if
			else
				if(DefectType(1)==1 .AND. DefectType(2)==0 .AND. DefectType(3)==0 .AND. DefectType(4)==0) then

					Diff=diffusivityCu(matNum)
					exit  outer1
				else
					Diff=DiffSingle(i,matNum)%D*dexp(-DiffSingle(i,matNum)%Em/(kboltzmann*temperature))
					exit outer1
				end if
			end if
		end if
	end do outer1

	if(i==numSingleDiff(matNum)+1) then	!did not find defect in single defect list
		do i=1,numFuncDiff(matNum)
			numSame=0
			do j=1,numSpecies
				if(defectType(j)==0 .AND. DiffFunc(i,matNum)%defectType(j)==0) then
					numSame=numSame+1
				else if(defectType(j) /= 0 .AND. DiffFunc(i,matNum)%defectType(j)==1) then
					if(defectType(j) >= DiffFunc(i,matNum)%min(j) .AND. &
							(defectType(j) <= DiffFunc(i,matNum)%max(j) .OR. DiffFunc(i,matNum)%max(j)==-1)) then
						numSame=numSame+1
					end if
				end if
			end do
			if(numSame==numSpecies) then

				Diff=DiffusivityCompute(defectType, DiffFunc(i,matNum)%functionType, DiffFunc(i,matNum)%numParam,&
						DiffFunc(i,matNum)%parameters, matNum)
				exit
			end if
		end do
		if(i==numFuncDiff(matNum)+1) then

			Diff=0d0
		end if
	end if

	findDiffusivity=Diff
end function

!*****************************************************************************************
!>double precision function DiffusivityCompute(DefectType, functionType, numParameters, parameters,matNum)
!computes diffusivity using a functional form for defects that don't have their diffusivity given by a value in a list.
!*****************************************************************************************
double precision function DiffusivityCompute(DefectType, functionType, numParameters, parameters,matNum)
	use mod_constants
	use mod_structures
	implicit none

	integer DefectType(numSpecies)
	integer functionType, numParameters, matNum,i
	double precision parameters(numParameters)
	double precision Diff
	double precision D0, Em
	double precision diffusivityCu

	if(functionType==1) then		!used for immobile defects
		Diff=0d0
	else if(functionType==2) then	!used for constant functions
		Diff=parameters(1)
	else if(functionType==3) then	!mobile SIA loops (6 parameters, Fe)
		D0=parameters(1)+parameters(2)/dble(DefectType(3))**(parameters(3))
		Em=parameters(4)+parameters(5)/dble(DefectType(3))**(parameters(6))
		Diff=D0*dexp(-Em/(kboltzmann*temperature))
	else if(functionType==4) then	!Cu diffusivity
		!< Dcu(n) = Dcu(1)/n
		Diff=diffusivityCu(matNum)/dble(DefectType(1))
	else if(functionType==5) then	!mobile W atoms (2 parameters: D0 and Em of W atom)
		D0=parameters(1)*dble(DefectType(3))**(-0.5d0)
		Diff=D0*dexp(-parameters(2)/(kboltzmann*temperature))
	else
		write(*,*) 'error incorrect diffusivity function chosen'
	endif

	DiffusivityCompute=Diff

end function

!**********************************************************************************
!This function is used to compute diffusivity of Cu atom
!**********************************************************************************
double precision function diffusivityCu(matNum)
	use mod_structures
	use mod_constants
	implicit none

	integer DefectType(numSpecies)
	integer matNum,i

	outer: do i=1,numSingleDiff(matNum)
		if(DiffSingle(i,matNum)%defectType(1)==1 .AND. DiffSingle(i,matNum)%defectType(2)==0 .AND. &
				DiffSingle(i,matNum)%defectType(3)==0 .AND. DiffSingle(i,matNum)%defectType(4)==0) then

			if(totalDPA > 0d0 .AND. dpaRate > 0d0) then
			!	diffusivityCu=(DiffSingle(i,matNum)%D*dexp(-DiffSingle(i,matNum)%Em/(kboltzmann*temperature)))* &
			!			(Vconcent/initialCeqv)
				diffusivityCu=(DiffSingle(i,matNum)%D*dexp(-DiffSingle(i,matNum)%Em/(kboltzmann*temperature)))* firr
				exit outer
			else
				diffusivityCu=(DiffSingle(i,matNum)%D*dexp(-DiffSingle(i,matNum)%Em/(kboltzmann*temperature)))
				exit outer
			end if
		end if
	end do outer

end function

!*****************************************************************************************
!>double precision function findBinding(matNum, DefectType, productType)
!returns the binding energy of a given defect type
!*****************************************************************************************
double precision function findBinding(matNum, DefectType, productType)
	use mod_structures
	use mod_constants
	implicit none

	integer DefectType(numSpecies), productType(numSpecies)
	integer i, j, numSame, numSameProduct, matNum
	double precision Eb
	double precision BindingCompute

	!Temporary: used as a parameter to vary the binding energy of all defects on GB
	double precision, parameter :: Param=0d0

	do i=1,numSingleBind(matNum)
		numSame=0
		numSameProduct=0
		do j=1,numSpecies
			if(DefectType(j)==BindSingle(i,matNum)%defectType(j)) then
				numSame=numSame+1
			end if
			if(productType(j)==BindSingle(i,matNum)%product(j)) then
				numSameProduct=numSameProduct+1
			end if
		end do

		if (numSame==numSpecies .AND. numSameProduct==numSpecies) then
			if(matNum==2) then

				Eb=BindSingle(i,matNum)%Eb-Param
				exit
			else
				Eb=BindSingle(i,matNum)%Eb
				exit
			end if
		end if
	end do

	if(i==numSingleBind(matNum)+1) then	!did not find defect in single defect list
		do i=1,numFuncBind(matNum)
			numSame=0
			numSameProduct=0
			do j=1,numSpecies

				if(DefectType(j)==0 .AND. BindFunc(i,matNum)%defectType(j)==0) then
					numSame=numSame+1
				else if(DefectType(j) /= 0 .AND. BindFunc(i,matNum)%defectType(j)==1) then
					if(DefectType(j) >= BindFunc(i,matNum)%min(j) .AND. &
							(DefectType(j) <= BindFunc(i,matNum)%max(j) .OR. BindFunc(i,matNum)%max(j)==-1)) then

						numSame=numSame+1
					end if
				end if

				if(productType(j)==0 .AND. BindFunc(i,matNum)%product(j)==0) then
					numSameProduct=numSameProduct+1
				else if(productType(j) == 1 .AND. BindFunc(i,matNum)%product(j)==1) then	!used to find dissociation binding energy
					numSameProduct=numSameProduct+1
				end if
			end do

			if(numSame==numSpecies .AND. numSameProduct==numSpecies) then

				if(matNum==2) then	!Adjust binding energies on GB

					Eb=BindingCompute(DefectType, productType, BindFunc(i,matNum)%functionType, &
							BindFunc(i,matNum)%numParam,BindFunc(i,matNum)%parameters)-Param
					exit

				else
					Eb=BindingCompute(DefectType, productType, BindFunc(i,matNum)%functionType, &
							BindFunc(i,matNum)%numParam,BindFunc(i,matNum)%parameters)
					exit
				end if
			end if
		end do
		if(i==numFuncBind(matNum)+1) then
			Eb=0d0
		end if
	end if

	if(Eb < 0d0) then
		Eb=0d0
	end if
	findBinding=Eb

end function

!*****************************************************************************************
!>double precision function BindingCompute(DefectType, product, functionType, numParameters, parameters)
!computes binding energy using a functional form for defects that don't have their binding energy given by a value in a list.
!*****************************************************************************************
double precision function BindingCompute(DefectType, product, functionType, numParameters, parameters)
	use mod_constants
	implicit none

	integer DefectType(numSpecies), product(numSpecies)
	integer functionType, numParameters, num, CuNum, VNum, SIANum, i
	double precision parameters(numParameters)
	double precision Eb

	if(functionType==12) then	!V / SIA cluster dislocation
		num=0
		do i=1,numSpecies
			if(DefectType(i) > num) then
				num=DefectType(i)
				exit
			end if
		end do
		Eb=parameters(1)+(parameters(2)-parameters(1))*(dble(num)**(2d0/3d0)-dble(num-1)**(2d0/3d0))/(2d0**(2d0/3d0)-1d0)
	else if(functionType==13) then	!nCu->Cu+(n-1)Cu
		CuNum=DefectType(1)
		Eb=parameters(1)*kboltzmann-parameters(2)*kboltzmann*tempStore- &
				(36d0*pi)**(1d0/3d0)*atomSize**(2d0/3d0)*parameters(3)*(dble(CuNum)**(2d0/3d0)-dble(CuNum-1)**(2d0/3d0))
	else if(functionType==14) then	!nCumV->Cu+(n-1)CumV
		CuNum=DefectType(1)
		VNum=DefectType(2)
		Eb=parameters(1)+parameters(2)*(dble(CuNum)**(0.85d0)-dble(CuNum+1)**(0.85d0))-&
				parameters(3)*(dble(VNum)**(1d0/3d0)-dble(VNum)**(2d0/3d0))
	else if(functionType==15) then	!nCumV->V+nCu(m-1)V
		CuNum=DefectType(1)
		VNum=DefectType(2)
		Eb=parameters(1)-parameters(2)*(dble(VNum)**(1d0/3d0)-dble(VNum+1)**(1d0/3d0))+&
				parameters(3)*(dble(VNum)**(2d0/3d0)-dble(VNum+1)**(2d0/3d0))-parameters(4)*dble(CuNum)*&
				(dble(VNum)**(1d0/3d0)-dble(VNum+1)**(1d0/3d0)+dble(VNum)**(2d0/3d0)-dble(VNum+1)**(2d0/3d0))
	else
		write(*,*) 'error incorrect Eb function chosen'
	end if

	BindingCompute=Eb

end function

!*****************************************************************************************
!>integer function findDefectSize(defectType)
!returns the size of a cluster
!NOTE: for Cu_nV_m clusters, this function returns the larger of m or n
!*****************************************************************************************
integer function findDefectSize(defectType)
	use mod_constants
	implicit none

	integer defectType(numSpecies), max, i

	!Hard-coded below and may be changed if the rules for defect size change.
	max=0
	do i=1, numSpecies
		if(defectType(i) > max) then
			max=defectType(i)
		end if
	end do

	findDefectSize=max
end function