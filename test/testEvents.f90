program testKernelSetup
!! Focal test program
!!
!! Based on testKernelSetup, this test uses a command queue pool with
!!  4 queues to test setting event dependencies and user events.
!!

use Focal
use Focal_Test_Utils
use iso_fortran_env, only: sp=>real32, dp=>real64
use clfortran, only: CL_EVENT_REFERENCE_COUNT
implicit none

type(fclCommandQPool) :: qPool
type(fclCommandQ), pointer :: cmdq
character(:), allocatable :: kernelSrc              ! Kernel source string
type(fclProgram) :: prog                            ! Focal program object
type(fclKernel) :: setInt_k, setFloat_k, setDouble_k, setChar_k
type(fclEvent) :: e(2), ue

real(sp), dimension(FCL_TEST_SIZE) :: hostReal32
real(dp), dimension(FCL_TEST_SIZE) :: hostReal64
integer, dimension(FCL_TEST_SIZE) :: hostInt32
character(1), dimension(FCL_TEST_SIZE), target :: hostChar

type(fclDeviceFloat) :: deviceReal32
type(fclDeviceDouble) :: deviceReal64
type(fclDeviceInt32) :: deviceInt32
type(fclDeviceBuffer) :: deviceBuffer

integer :: i
integer(c_int32_t) :: n

! --- Initialise ---
call fclTestInit()

qPool = fclCreateCommandQPool(3,ocl_device,enableProfiling=.true.,&
                            blockingRead=.false., blockingWrite=.false.)

ue = fclCreateUserEvent()


! --- Initialise device buffers ---
call fclInitBuffer(deviceInt32,FCL_TEST_SIZE)
call fclInitBuffer(deviceReal32,FCL_TEST_SIZE)
call fclInitBuffer(deviceReal64,FCL_TEST_SIZE)
call fclInitBuffer(deviceBuffer,c_sizeof(hostChar))

! --- Initialise kernels ---
call fclGetKernelResource(kernelSrc)
prog = fclCompileProgram(kernelSrc)
setInt_k = fclGetProgramKernel(prog,'setInt32Test',[FCL_TEST_SIZE])
setFloat_k = fclGetProgramKernel(prog,'setFloatTest',[FCL_TEST_SIZE])
setDouble_k = fclGetProgramKernel(prog,'setDoubleTest',[FCL_TEST_SIZE])
setChar_k = fclGetProgramKernel(prog,'setCharTest',[FCL_TEST_SIZE])

! Launch first kernel
call fclSetDependency(ue)
call setInt_k%launch(qPool%next(),FCL_TEST_SIZE,deviceInt32)

cmdq => qPool%current()
call fclTestAssert(cmdq%lastKernelEvent%cl_event > 0,'cmdq%lastKernelEvent%cl_event > 0')
call fclTestAssert(fclLastKernelEvent%cl_event == cmdq%lastKernelEvent%cl_event, &
                    'fclLastKernelEvent%cl_event == cmdq%lastKernelEvent%cl_event')

call fclGetEventInfo(fclLastKernelEvent,CL_EVENT_REFERENCE_COUNT,n)
call fclTestAssert(n==2,'fclLastKernelEvent == 2')

e(1) = fclLastKernelEvent

call fclGetEventInfo(fclLastKernelEvent,CL_EVENT_REFERENCE_COUNT,n)
call fclTestAssert(n==3,'fclLastKernelEvent == 3')

! ReLaunch first kernel
call fclSetDependency(ue)
call setInt_k%launch(qPool%current(),FCL_TEST_SIZE,deviceInt32)

call fclGetEventInfo(e(1),CL_EVENT_REFERENCE_COUNT,n)
call fclTestAssert(n==1,'e(1) == 1')
write(*,*) n

! Launch second kernel: dependency on first
call fclSetDependency(qPool%next(),fclLastKernelEvent)

cmdq => qPool%current()
call fclTestAssert(transfer(cmdq%dependencyListPtr,int(1,c_intptr_t)) == &
                     transfer(c_loc(cmdq%dependencyList),int(1,c_intptr_t)), &
                    'fclSetDependency_Event:dependencyListPtr:set')


call fclTestAssert(cmdq%dependencyList(1)==fclLastKernelEvent%cl_event, &
                      'fclSetDependency_Event:dependencyList')

call fclTestAssert(cmdq%nDependency==1, &
                      'fclSetDependency_Event:ndependency:set')

call setFloat_k%launch(qPool%current(),FCL_TEST_SIZE,deviceReal32)
call fclTestAssert(transfer(cmdq%dependencyListPtr,int(1,c_intptr_t)) == &
                     transfer(C_NULL_PTR,int(1,c_intptr_t)), &
                    'fclLaunchKernel:dependencyListPtr:cleared')

call fclTestAssert(cmdq%nDependency==0, &
                    'fclLaunchKernel:ndependency:unset')

e(2) = fclLastKernelEvent

! Launch third kernel: dependency on first and second
call fclSetDependency(qPool%next(),e)

cmdq => qPool%current()
call fclTestAssert(transfer(cmdq%dependencyListPtr,int(1,c_intptr_t)) == &
                     transfer(c_loc(cmdq%dependencyList),int(1,c_intptr_t)), &
                    'fclSetDependency_Eventlist:dependencyListPtr:set')


call fclTestAssert(all(cmdq%dependencyList(1:2)==e(1:2)%cl_event), &
                      'fclSetDependency_Eventlist:dependencyList')

call fclTestAssert(cmdq%nDependency==2, &
                      'fclSetDependency_Eventlist:ndependency:set')

call setDouble_k%launch(qPool%current(),FCL_TEST_SIZE,deviceReal64)


call fclTestAssert(transfer(cmdq%dependencyListPtr,int(1,c_intptr_t)) == &
                     transfer(C_NULL_PTR,int(1,c_intptr_t)), &
                    'fclLaunchKernel:dependencyListPtr:cleared (2)')

call fclTestAssert(cmdq%nDependency==0, &
                    'fclLaunchKernel:ndependency:unset (2)')

! Launch fourth kernel on default command queue: dependency on first and second
call setChar_k%setArgs(FCL_TEST_SIZE,deviceBuffer)
call setChar_k%launchAfter(e)

! Relaunch fourth kernel, dependency on third kernel
call setChar_k%launchAfter(cmdq%lastKernelEvent)

cmdq => fclDefaultCmdQ
call fclTestAssert(transfer(cmdq%dependencyListPtr,int(1,c_intptr_t)) == &
                     transfer(C_NULL_PTR,int(1,c_intptr_t)), &
                    'dependencyListPtr:unset (3)')

call fclTestAssert(cmdq%nDependency==0, &
                    'ndependency:unset (3)')


call fclSetUserEvent(ue)
call fclWait(fclDefaultCmdQ%lastKernelEvent)
call fclWait(qPool)




! --- Transfer device buffers to host ---
call fclSetDependency(qPool%queues(:)%lastKernelEvent,hold=.true.)

call fclTestAssert(fclDefaultCmdQ%nDependency==3, &
                      'fclSetDependency_EventList:fclDefaultCmdQ:ndependency:set')

call fclTestAssert(transfer(fclDefaultCmdQ%dependencyListPtr,int(1,c_intptr_t)) == &
                      transfer(c_loc(fclDefaultCmdQ%dependencyList),int(1,c_intptr_t)), &
                     'fclSetDependency_EventList:fclDefaultCmdQ:dependencyListPtr:set')

hostInt32 = deviceInt32

call fclTestAssert(fclDefaultCmdQ%nDependency==3, &
                      'fclSetDependency_EventList:fclDefaultCmdQ:ndependency:set (2)')

hostReal32 = deviceReal32

call fclTestAssert(fclDefaultCmdQ%nDependency==3, &
                      'fclSetDependency_EventList:fclDefaultCmdQ:ndependency:set (3)')

hostReal64 = deviceReal64

call fclTestAssert(fclDefaultCmdQ%nDependency==3, &
                      'fclSetDependency_EventList:fclDefaultCmdQ:ndependency:set (4)')

call fclMemRead(c_loc(hostChar),deviceBuffer,c_sizeof(hostChar))

call fclTestAssert(fclDefaultCmdQ%nDependency==3, &
                      'fclSetDependency_EventList:fclDefaultCmdQ:ndependency:set (5)')

call fclClearDependencies()

call fclTestAssert(transfer(fclDefaultCmdQ%dependencyListPtr,int(1,c_intptr_t)) == &
                     transfer(C_NULL_PTR,int(1,c_intptr_t)), &
                    'fclClearDependencies:fclDefaultCmdQ:dependencyListPtr:unset')

call fclTestAssert(fclDefaultCmdQ%nDependency==0, &
                    'fclClearDependencies:fclDefaultCmdQ:nDependency:unset')


! --- Check arrays ---
call fclTestAssertEqual([sum(hostInt32)],[sum([(i,i=0,FCL_TEST_SIZE-1)])],'sum(hostInt32)')
call fclTestAssertEqual([sum(hostReal32)],[sum([(1.0*i,i=0,FCL_TEST_SIZE-1)])],'sum(hostReal32)')
call fclTestAssertEqual([sum(hostReal64)],[sum([(1.0d0*i,i=0,FCL_TEST_SIZE-1)])],'sum(hostReal64)')
call fclTestAssertEqual(hostChar,[('a',i=0,FCL_TEST_SIZE-1)],'hostChar')

call fclFreeBuffer(deviceInt32)
call fclFreeBuffer(deviceReal32)
call fclFreeBuffer(deviceReal64)
call fclFreeBuffer(deviceBuffer)

call fclTestFinish()

end program testKernelSetup
! -----------------------------------------------------------------------------
