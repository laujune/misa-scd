
!***************************************************************************************************
!>Subroutine: Choose Cascade
!!Takes list of cascades (read from input file) and chooses one randomly
!!
!!Inputs: CascadeList (global variable)
!!Output: CascadeTemp (pointing at the cascade we want)
!***************************************************************************************************

subroutine chooseCascade(CascadeTemp)
use DerivedType
use randdp
use mod_constants
implicit none

type(cascadeEvent), pointer :: cascadeTemp
double precision r, atemp

r=dprand()
atemp=0d0
cascadeTemp=>CascadeList

do while(associated(cascadeTemp))
	atemp=atemp+1d0/dble(numCascades)
	if(atemp >= r) then
		exit
	end if
	cascadeTemp=>cascadeTemp%nextCascade
end do
end subroutine

!***************************************************************************************************
!> Integer function cascadeCount()
!
! This subroutine counts how many cascades are active in the LOCAL mesh (not on all processors)
! and returns that value
!
! Inputs: none
! Outputs: number of cascades present
!***************************************************************************************************

integer function CascadeCount()
use mod_constants
use DerivedType
implicit none

type(cascade), pointer :: CascadeCurrent
integer count

CascadeCurrent=>ActiveCascades
	
count=0

do while(associated(CascadeCurrent))
	count=count+1
	
	CascadeCurrent=>CascadeCurrent%next
end do

CascadeCount=count

end function

!***************************************************************************************************
!> subroutine addCascadeExplicit
!
! This subroutine takes the place of chooseReaction in the case of explicit cascade implantation.
! It forces the program to 'choose' a cascade reaction, instead of using the Monte Carlo algorithm
! to do so.
!
! Inputs: none
! Outputs: reactionCurrent and CascadeCurrent, pointing at cascade reaction.
!***************************************************************************************************

subroutine addCascadeExplicit(reactionCurrent)
use DerivedType
use mod_constants
use randdp
implicit none

type(reaction), pointer :: reactionCurrent
double precision r2, atemp, r2timesa
integer i

!***************************************************************************************************
!Choose from cascades within the coarse mesh (choose which element to implant cascades in)
!***************************************************************************************************

atemp=0d0
r2=dprand()
r2timesa=r2*numCells

outer: do i=1,numCells

	reactionCurrent=>reactionList(i)	!Point reactionCurrent at the cascade implantation reaction in each volume element
	
	atemp=atemp+1d0		!Here we don't have a reaction rate, and each cell is weighted evenly (assuming uniform mesh)
	if(atemp >= r2timesa) then
		exit outer			!exit both loops with reactionCurrent pointing to the randomly chosen reaction
	endif

end do outer

!Checking that reactionCurrent is pointed at the correct reaction
if(implantType=='Cascade') then

	if(reactionCurrent%numReactants==-10 .AND. reactionCurrent%numProducts==0) then !Cascade implantation
!		numImplantEvents=numImplantEvents+1
		numImpAnn(1)=numImpAnn(1)+1
	end if

else
	write(*,*) 'Error wrong implant type for explicit procedure'
end if

end subroutine

!***************************************************************************************************
!> logical function cascadeMixingCheck()
!
! cascadeMixingCheck checks whether a given defect in the fine mesh interacts with the cascade. It
! returns a logical value of true or false.
!
! Input: none
! Output: logical value for whether or not a fine mesh defect combines with a cascade.
!***************************************************************************************************

logical function cascadeMixingCheck()
use mod_constants
use randdp
implicit none

double precision r1, probability
logical boolean

!step 1: calculate the volume fraction of defectTemp in the cell

!Current version (n cascade mixing checks)
probability=cascadeVolume/(numCellsCascade*CascadeElementVol)
!write(*,*) 'mixing probability', probability

!step 4: use random number to decide on interaction
r1=dprand()
if(r1 > probability) then
	boolean=.FALSE.
else
	boolean=.TRUE.
endif

cascadeMixingCheck=boolean

end function

!***************************************************************************************************
!> Subroutine CascadeUpdateStep(cascadeCell)
!
! Carries out the communication necessary when a cascade is created or destroyed in an element
! that bounds another processor.
!
! Step 1: Check to see if cascade was created/destroyed in element that is in the boundary of another
! processor.
!
! Step 2: Send message to neighboring processors about whether a cascade was created/destroyed in their
! boundaries, and if so the number of defects to recieve in the boundary element
!
! Step 3: Send/recieve boundary element defects (just completely re-write boundary element defects in this step)
!
! Step 4: Update reaction rates for all diffusion reactions from elements neighboring the boundary
!	elements which have been updated
!
! Inputs: cascadeCell (integer, 0 if no cascade, otherwise gives number of volume element that cascade
!	event has occurred in)
!
! Outputs: none
!
! Actions: see above, sends/recieves information on boundary updates and updates reaction lists.
!***************************************************************************************************

subroutine cascadeUpdateStep(cascadeCell)
use DerivedType
use mod_constants
use ReactionRates
implicit none
include 'mpif.h'

integer cascadeCell

integer i, j, k, tag, cellInfoBuffer(5,6), count
integer status(MPI_STATUS_SIZE), request
!integer, allocatable :: defectBuffer(:,:)
double precision, allocatable :: defectBuffer(:,:)
type(defect), pointer :: defectCurrent, defectPrev

integer cellNumber, bndryCellNumber, numDefects, cellVol, defectType(numSpecies)
integer numSend, numRecv, bufferCount, sendBufferCount, sendCount, numBuffersRecv
integer recvInfoBuffer(5)
integer, allocatable :: recvDefectBuffer(:,:)
integer localGrainID, neighborGrainID

logical flag
integer tempCount,recvDir

integer sendRequest, recvRequest
integer sendStatus(MPI_STATUS_SIZE),recvStatus(MPI_STATUS_SIZE)

interface
	subroutine findDefectInList(defectCurrent, defectPrev, defectType)
		use DerivedType
		use mod_constants
		implicit none
		type(defect), pointer :: defectCurrent, defectPrev
		integer defectType(numSpecies)
	end subroutine
end interface

! Step 1: Check to see if cascade was created/destroyed in element that is in the boundary of another processor.
if(cascadeCell/=0) then

	!write(86,*) 'Cascade Update Step 1: creating and sending buffers'
	defectCurrent=>defectList(cascadeCell)%next
	count=0

	outer: do j=1,6
		do k=1,myMesh(cascadeCell)%numNeighbors(j)
			if(myMesh(cascadeCell)%neighborProcs(k,j) /= myProc%taskid .AND. &
					myMesh(cascadeCell)%neighborProcs(k,j) /= -1) then

				do while(associated(defectCurrent))
					count=count+1
					defectCurrent=>defectCurrent%next
				end do

				exit outer

			end if
		end do
	end do outer

	if(count /=0 ) then
		allocate(defectBuffer(numSpecies+1,count+1))

		defectBuffer(1,1)=0		!myMesh(cascadeCell)%neighbors(k,dir)
		defectBuffer(2,1)=0		!numDefects
		defectBuffer(3,1)=0d0	!myMesh(cascadeCell)%volume
		defectBuffer(4,1)=0		!cascadeCell
		defectBuffer(5,1)=0		!useless

		defectCurrent=>defectList(cascadeCell)%next

		do i=1,count

			defectBuffer(1:numSpecies,i+1)=defectCurrent%defectType(:)

			defectBuffer(numSpecies+1,i+1)=defectCurrent%num
			defectCurrent=>defectCurrent%next
		end do

	end if

	do j=1,6

		!Send
		do k=1,myMesh(cascadeCell)%numNeighbors(j)

			if(myMesh(cascadeCell)%neighborProcs(k,j) /= myProc%taskid .AND. &
					myMesh(cascadeCell)%neighborProcs(k,j) /= -1) then

				defectBuffer(1,1)=myMesh(cascadeCell)%neighbors(k,j)
				defectBuffer(2,1)=count
				defectBuffer(3,1)=myMesh(cascadeCell)%volume
				defectBuffer(4,1)=cascadeCell

				tag=myMesh(cascadeCell)%neighborProcs(k,j)
				call MPI_WAIT(sendRequest, snedStatus, ierr)

				call MPI_ISEND(defectBuffer, (numSpecies+1)*count, MPI_DOUBLE_PRECISION, &
						myMesh(cascadeCell)%neighborProcs(k,j), tag, comm,sendRequest, ierr)

			end if
		end do

		!We have to switch the tags on MPI_RECV in order for the correct send/recieve pair to be exchanged
		if(mod(j,2)==0) then
			recvDir=j-1
		else
			recvDir=j+1
		end if

		!if the neighboring proc is not a free surface (no proc)
		if(myProc%procNeighbor(recvDir) /= -1 .AND. myProc%procNeighbor(recvDir) /= myProc%taskid) then

			!write(86,*) 'Recieving info proc', myProc%taskid, 'from', myProc%procNeighbor(tag), 'tag', tag
			tempCount=0
			flag=.FALSE.
			tag=myProc%procNeighbor(recvDir)
			call MPI_IPROBE(myProc%procNeighbor(recvDir), tag, comm,flag,status,ierr)
			if(flag .eqv. .TRUE.) then
				call MPI_GET_COUNT(status,MPI_DOUBLE_PRECISION,tempCount,ierr)
				numRecv=tempCount/(numSpecies+1)

				if(numRecv /= 0) then

					allocate(recvDefectBuffer,(numSpecies+1,numRecv+1))

					call MPI_IRECV(recvDefectBuffer,(numSpecies+1)*numRecv,MPI_DOUBLE_PRECISION,&
							myProc%procNeighbor(recvDir),tag,comm,recvRequest,ierr)
					call MPI_WAIT(recvRequest, recvStatus, ierr)

					bndryCellNumber=recvDefectBuffer(4,1)
					cellNumber=recvDefectBuffer(1,1)

					myBoundary(bndryCellNumber,recvDir)%volume=recvDefectBuffer(3,1)

					!remove defects from myBoundary (except for first defect, this is all 0's and is just a placeholder)
					defectCurrent=>myBoundary(bndryCellNumber,recvDir)%defectList%next

					!delete exiting defects
					nullify(defectPrev)
					do while(associated(defectCurrent))
						defectPrev=>defectCurrent
						defectCurrent=>defectCurrent%next
						deallocate(defectPrev%defectType)
						deallocate(defectPrev)
					end do

					!nullify the %next pointer in the first element of the defect list
					defectCurrent=>myBoundary(bndryCellNumber,recvDir)%defectList

					!add defects
					do i=1,numRecv-1
						nullify(defectCurrent%next)
						allocate(defectCurrent%next)
						nullify(defectCurrent%next%next)
						defectCurrent=>defectCurrent%next
						allocate(defectCurrent%defectType(numSpecies))
						defectCurrent%cellNumber=bndryCellNumber
						defectCurrent%num=recvDefectBuffer(numSpecies+1,i+1)

						defectCurrent%defectType(:)=recvDefectBuffer(1:numSpecies,i+1)
					end do

					deallocate(recvDefectBuffer)

					!*******************
					!Add Diffusion reactions
					!*******************

					!point defectCurrent at defect list in local cell
					defectCurrent=>defectList(cellNumber)

					do while(associated(defectCurrent))
						if (myMesh(cellNumber)%numNeighbors(recvDir)==0) then
							write(*,*) 'error myMesh does not have neighbors in this direction'
						end if

						if(polycrystal=='yes') then

							!Find the grain ID number of the volume element we are in
							localGrainID=myMesh(cellNumber)%material

							!Find the grain ID number of the neighboring volume element
							!NOTE: here we don't need to worry about free surfaces, since
							!we are only adding diffusion reactions due to defects that
							!have changed on the boundary of this processor (in another
							!processor, not a free surface)
							if(myProc%procNeighbor(recvDir)/=myProc%taskid .AND. myProc%procNeighbor(recvDir)/=-1) then
								neighborGrainID=myBoundary(myMesh(cellNumber)%neighbors(1,recvDir),recvDir)%material
							else
								neighborGrainID=myMesh(myMesh(cellNumber)%neighbors(1,recvDir))%material
							end if

							if(localGrainID==neighborGrainID) then
								!Allow diffusion between elements in the same grain
								call addDiffusionReactions(cellNumber, bndryCellNumber,&
										myProc%taskid, myProc%procNeighbor(recvDir),recvDir,defectCurrent%defectType)
							else
								!Assume perfect sinks at grain boundaries - treat grain boundaries like free surfaces for now
								call addDiffusionReactions(cellNumber, 0, myProc%taskid, -1, recvDir, defectCurrent%defectType)
							end if
						else
							!Add diffusion reactions from this cell to neighboring cells
							call addDiffusionReactions(cellNumber, bndryCellNumber,&
									myProc%taskid, myProc%procNeighbor(recvDir),recvDir,defectCurrent%defectType)
						end if
						defectCurrent=>defectCurrent%next
					end do
				end if
			end if

		end if
	end do

	if(allocated(defectBuffer)) then
		deallocate(defectBuffer)
	end if
end if

!if(cascadeCell==0) then

	!do nothing, no cascade
	!write(86,*) 'No Cascade'
!	do j=1,6
!		cellInfoBuffer(1,j)=0
!		cellInfoBuffer(2,j)=0
!		cellInfoBuffer(3,j)=0
!		cellInfoBuffer(4,j)=0
!		cellInfoBuffer(5,j)=0

		!Only send/recv if the neighboring proc is different from this one
!		if(myProc%procNeighbor(j) /= -1 .AND. myProc%procNeighbor(j) /= myProc%taskid) then
!			call MPI_SEND(cellInfoBuffer(:,j), 5, MPI_INTEGER,myProc%procNeighbor(j),251+j,comm,ierr)
!		endif

!	end do

!else
	!write(86,*) 'Cascade Update Step 1: creating and sending buffers'
!	do j=1,6

!		do k=1,myMesh(cascadeCell)%numNeighbors(j)

!			if(myMesh(cascadeCell)%neighborProcs(k,j) /= myProc%taskid .AND. &
!				myMesh(cascadeCell)%neighborProcs(k,j) /= -1) then

				!this element has a neighbor that is on a different processor

				!cell number in neighboring proc
!				cellInfoBuffer(1,j)=myMesh(cascadeCell)%neighbors(k,j)

				!local cell number
!				cellInfoBuffer(4,j)=cascadeCell

				!Find out how many defects are in this volume element
!				defectCurrent=>defectList(cascadeCell)%next
!				count=0
!				sendBufferCount=0	!Buffer counter

!				do while(associated(defectCurrent))

!					count=count+1

!					defectCurrent=>defectCurrent%next
!				end do

!				if(mod(count,maxBufferSize)==0) then
!					sendBufferCount = count/maxBufferSize
!					count = maxBufferSize
!				else
!					sendBufferCount = count/maxBufferSize + 1
!					count = mod(count,maxBufferSize)
!				end if

!				cellInfoBuffer(2,j)=count
!				cellInfoBuffer(5,j)=sendBufferCount

				!Update volume (to send to boundary mesh in neighbor): after cascade addition/deletion,
				!cell volume will have changed
!				cellInfoBuffer(3,j)=myMesh(cascadeCell)%volume

				!Send info to neighbor: first send size of defectBuffer, then send defectBuffer
				!if(myProc%taskid==MASTER) write(*,*) j, 'sending buffer', 101+j

				!write(86,*) 'Sending full buffer, proc', myProc%taskid, 'to', &
				!	myMesh(cascadeCell)%neighborProcs(k,j), 'tag', 251+j
				!write(86,*) 'dir', j, 'numNeighbors', myMesh(cascadeCell)%numNeighbors(j), 'k', k
				!write(86,*) 'cellInfoBuffer', cellInfoBuffer(:,j)

!				call MPI_SEND(cellInfoBuffer(:,j), 5, MPI_INTEGER,myMesh(cascadeCell)%neighborProcs(k,j),&
!					251+j,comm,ierr)

!				defectCurrent=>defectList(cascadeCell)%next

!				do bufferCount=1,sendBufferCount

					!All defect buffers have maxBufferSize defects except for the last
!					if(bufferCount==sendBufferCount) then
!						allocate(defectBuffer(numSpecies+1,cellInfoBuffer(2,j)))
!						numSend=cellInfoBuffer(2,j)
!					else
!						allocate(defectBuffer(numSpecies+1,maxBufferSize))
!						numSend=maxBufferSize
!						write(*,*) 'Chopped down to ',maxBufferSize,'Proc', myProc%taskid
!					endif

					!Re-loop through defects and add each type to the defect buffer
!					sendCount=0

!					do while(associated(defectCurrent))
!						sendCount=sendCount+1

!						if(sendCount > maxBufferSize) then
!							exit
!						endif

!						do i=1,numSpecies
!							defectBuffer(i,sendCount)=defectCurrent%defectType(i)
!						end do

!						defectBuffer(numSpecies+1,sendCount)=defectCurrent%num
!						defectCurrent=>defectCurrent%next
!					end do

					!write(86,*) 'Info sent, sending buffer. Size', cellInfoBuffer(j,2)*(numSpecies+1)

!					call MPI_ISEND(defectBuffer, (numSpecies+1)*numSend, MPI_INTEGER, &
!						myMesh(cascadeCell)%neighborProcs(k,j), 351*j+bufferCount, comm,request, ierr)

					!write(86,*) 'Buffer sent'

!					deallocate(defectBuffer)

!				end do

!			else if(myMesh(cascadeCell)%neighborProcs(k,j) /= -1 .AND. &
!				myProc%procNeighbor(j) /= myProc%taskid) then

				!Tag shows that neighboring cell is not in another processor
!				cellInfoBuffer(1,j)=0
!				cellInfoBuffer(2,j)=0
!				cellInfoBuffer(3,j)=0
!				cellInfoBuffer(4,j)=0
!				cellInfoBuffer(5,j)=0

				!write(86,*) 'Sending empty buffer, proc', myProc%taskid, 'to', &
				!	myProc%procNeighbor(j)

!				call MPI_SEND(cellInfoBuffer(:,j), 5, MPI_INTEGER,myProc%procNeighbor(j),&
!					251+j,comm,ierr)

!			else if(myMesh(cascadeCell)%neighborProcs(k,j) == -1) then

				!Here, even if we are at a free surface, we send a blank buffer set to the other proc
				!because the proc mesh is periodic even when the actual mesh has free surfaces.

!				cellInfoBuffer(1,j)=0
!				cellInfoBuffer(2,j)=0
!				cellInfoBuffer(3,j)=0
!				cellInfoBuffer(4,j)=0
!				cellInfoBuffer(5,j)=0

				!write(86,*) 'Sending empty buffer, proc', myProc%taskid, 'to', &
				!	myProc%procNeighbor(j)

!				call MPI_SEND(cellInfoBuffer(:,j), 5, MPI_INTEGER,myProc%procNeighbor(j),&
!					251+j,comm,ierr)

				!Do nothing, free surface

!			else if(myProc%procNeighbor(j)==myProc%taskid) then

				!Do nothing PBCs point towards same proc

				!write(86,*) 'doing nothing, periodic BCs'

!			else

!				write(*,*) 'error sending in cascadeUpdateStep'

!			end if

!		end do
!	end do
!end if

!Recieve cellInfoBuffer and boundary element defects, if any
!write(86,*) 'Cascade Update Step 2: Recieving Info'
!do i=1,6
	
	!We have to switch the tags on MPI_RECV in order for the correct send/recieve pair to be exchanged
!	if(i==1 .OR. i==3 .OR. i==5) then
!		tag=i+1
!	else
!		tag=i-1
!	endif
	
	!if the neighboring proc is not a free surface (no proc)
!	if(myProc%procNeighbor(i) /= -1 .AND. myProc%procNeighbor(i) /= myProc%taskid) then
		
		!write(86,*) 'Recieving info proc', myProc%taskid, 'from', myProc%procNeighbor(i), 'tag', 251+tag
		
		!if(myProc%taskid==MASTER) write(*,*) i, 'receiving', 101+tag
!		call MPI_RECV(recvInfoBuffer,5,MPI_INTEGER,myProc%procNeighbor(i),&
!			251+tag,comm,status,ierr)
		
		!write(86,*) 'Info Recvd'
	
		!LOCAL cell number
!		cellNumber=recvInfoBuffer(1)
!		numDefects=recvInfoBuffer(2)
!		cellVol=recvInfoBuffer(3)
!		bndryCellNumber=recvInfoBuffer(4)
!		numBuffersRecv=recvInfoBuffer(5)

		!if(myProc%taskid==MASTER) write(*,*) 'local cell number', cellNumber
		
!		if(cellNumber /= 0) then
			
			!Dividing up buffers in order to not surpass the maximum amount
			!of data that can be sent using MPI_ISEND. All buffers except for
			!the last will have maxBufferSize*(numSpecies+1) integers in them

			!write(86,*) 'Recieving info buffer proc', myProc%taskid, &
			!	'from', myProc%procNeighbor(i)
			
			!Add defects in recvDefectBuffer to correct boundary element (remove all other defects from boundary element first)
			!and change the volume of the bondary mesh element
!			myBoundary(bndryCellNumber,i)%volume=cellVol
			
			!remove defects from myBoundary (except for first defect, this is all 0's and is just a placeholder)
!			defectCurrent=>myBoundary(bndryCellNumber,i)%defectList%next

!			nullify(defectPrev)
!			do while(associated(defectCurrent))
!				defectPrev=>defectCurrent
!				defectCurrent=>defectCurrent%next
!				deallocate(defectPrev%defectType)
!				deallocate(defectPrev)
!			end do
			
			!nullify the %next pointer in the first element of the defect list
!			defectCurrent=>myBoundary(bndryCellNumber,i)%defectList

!			do bufferCount=1,numBuffersRecv
				
				!All buffers other than the final one are full (maxBufferSize defects)
!				if(bufferCount==numBuffersRecv) then
!					numRecv=numDefects
!				else
!					numRecv=maxBufferSize
!				end if
				
				!if(myProc%taskid==MASTER) write(*,*) 'recieving buffer', bufferCount, 'numDefectsRecv', numRecv
					
!				allocate(recvDefectBuffer(numSpecies+1,numRecv))
				
!				call MPI_IRECV(recvDefectBuffer,(numSpecies+1)*numRecv,MPI_INTEGER,myProc%procNeighbor(i),&
!					351*tag+bufferCount,comm,request,ierr)
					
!				call MPI_WAIT(request, status, ierr)
				
				!write(86,*) 'Buffer recieved'
			
				!add defects in recvDefectBuffer to boundary element
!				do j=1,numRecv

!					nullify(defectCurrent%next)
!					allocate(defectCurrent%next)
!					nullify(defectCurrent%next%next)
!					defectCurrent=>defectCurrent%next
!					allocate(defectCurrent%defectType(numSpecies))
!					defectCurrent%cellNumber=bndryCellNumber
!					defectCurrent%num=recvDefectBuffer(numSpecies+1,j)
!					do k=1, numSpecies
!						defectCurrent%defectType(k)=recvDefectBuffer(k,j)
!					end do

!				end do
					
!				deallocate(recvDefectBuffer)
				
!			end do
				
			!Update diffusion rates from LOCAL element into recvInfoBuffer(4) in boundary
			
			!*******************
			!Add Diffusion reactions
			!*******************
			
			!point defectCurrent at defect list in local cell
!			defectCurrent=>defectList(cellNumber)
			
!			do while(associated(defectCurrent))
!				if (myMesh(cellNumber)%numNeighbors(i)==0) then
!					write(*,*) 'error myMesh does not have neighbors in this direction'
!				end if
				
!				if(polycrystal=='yes') then
				
					!Find the grain ID number of the volume element we are in
!					localGrainID=myMesh(cellNumber)%material
					
					!Find the grain ID number of the neighboring volume element
					!NOTE: here we don't need to worry about free surfaces, since
					!we are only adding diffusion reactions due to defects that
					!have changed on the boundary of this processor (in another
					!processor, not a free surface)
!					if(myProc%procNeighbor(i) /= myProc%taskid .AND. &
!						myProc%procNeighbor(i) /= -1) then
!						neighborGrainID=myBoundary(myMesh(cellNumber)%neighbors(1,i),i)%material
!					else
!						neighborGrainID=myMesh(myMesh(cellNumber)%neighbors(1,i))%material
!					endif
					
!					if(localGrainID==neighborGrainID) then
						!Allow diffusion between elements in the same grain
!						call addDiffusionReactions(cellNumber, bndryCellNumber,&
!							myProc%taskid, myProc%procNeighbor(i),i,defectCurrent%defectType)
!					else
						!Assume perfect sinks at grain boundaries - treat grain boundaries like free surfaces for now
!						call addDiffusionReactions(cellNumber, 0, myProc%taskid, -1, i, defectCurrent%defectType)
!					end if
				
!				else
					!Add diffusion reactions from this cell to neighboring cells
!					call addDiffusionReactions(cellNumber, bndryCellNumber,&
!						myProc%taskid, myProc%procNeighbor(i),i,defectCurrent%defectType)
!				end if
				
!				defectCurrent=>defectCurrent%next
!			end do
		
!		endif
		
!	else
		!Do nothing, free surface
!	end if
	
!end do

end subroutine

!***************************************************************************************************
!> subroutine createCascadeConnectivity()
!
! This subroutine assigns values to the connectivity matrix (global variable) used for all cascades
!
! Input: numxcascade, numycascade, nunmzcascade (global variables) : from parameters.txt
! Output: cascadeConnectivity (global variable)
!***************************************************************************************************

subroutine createCascadeConnectivity()
use mod_constants

implicit none

integer cell
!************************************************
!PBCs in x and y, free in z (cell 0 represents free surface)
!************************************************
do cell=1,numCellsCascade
	if(mod(cell,numxcascade)==0) then !identify cell to the right
		!cascadeConnectivity(cell, 1)=cell-numxcascade+1
		cascadeConnectivity(1, cell)=0	!free in x
	else
		cascadeConnectivity(1, cell)=cell+1
	end if
	
	if(mod(cell+numxcascade-1,numxcascade)==0) then !identify cell to the left
		!cascadeConnectivity(cell,2)=cell+numxcascade-1
		cascadeConnectivity(2, cell)=0	!free in x
	else
		cascadeConnectivity(2, cell)=cell-1
	end if
	
	if(mod(cell,numxcascade*numycascade) > numxcascade*(numycascade-1) .OR. &
		mod(cell,numxcascade*numycascade)==0) then
		cascadeConnectivity(3, cell)=0	!free in y
		!cascadeConnectivity(cell,3)=cell-(numxcascade*(numycascade-1))
	else
		cascadeConnectivity(3, cell)=cell+numxcascade
	end if
	
	if(mod(cell,numxcascade*numycascade) <= numxcascade .AND. mod(cell, numxcascade*numycascade) /= 0) then
		cascadeConnectivity(4, cell)=0	!free in y
		!cascadeConnectivity(cell,4)=cell+(numxcascade*(numycascade-1))
	else
		cascadeConnectivity(4, cell)=cell-numxcascade
	end if
	
	if(mod(cell,numxcascade*numycascade*numzcascade) > numxcascade*numycascade*(numzcascade-1) .OR. &
		mod(cell, numxcascade*numycascade*numzcascade)==0) then
		
		cascadeConnectivity(5, cell)=0	!free in z
	else
		cascadeConnectivity(5, cell)=cell+numxcascade*numycascade
	end if
	
	if(mod(cell,numxcascade*numycascade*numzcascade) <= numxcascade*numycascade .AND. &
		mod(cell,numxcascade*numycascade*numzcascade) /= 0) then
		
		cascadeConnectivity(6, cell)=0	!free in z
	else
		cascadeConnectivity(6, cell)=cell-numxcascade*numycascade
	end if
end do

end subroutine
