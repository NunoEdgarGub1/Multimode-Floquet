!export LD_LIBRARY_PATH="/opt/intel/compilers_and_libraries_2017/linux/mkl/lib/intel64"; 
PROGRAM MULTIMODEFLOQUET

  USE ATOMIC_PROPERTIES
  USE TYPES
  USE SPARSE_INTERFACE
  USE SUBINTERFACE
  USE SUBINTERFACE_LAPACK
  USE FLOQUETINITINTERFACE
  USE ARRAYS 

  IMPLICIT NONE
  TYPE(MODE),       DIMENSION(:),   ALLOCATABLE :: FIELDS
  TYPE(ATOM)                                       ID
  INTEGER,          DIMENSION(:),   ALLOCATABLE :: MODES_NUM
  INTEGER                                          TOTAL_FREQUENCIES,D_MULTIFLOQUET
  INTEGER                                          INFO,m,INDEX0,r
  DOUBLE PRECISION, DIMENSION(:),   ALLOCATABLE :: ENERGY,E_FLOQUET
  COMPLEX*16,       DIMENSION(:,:), ALLOCATABLE :: U_F,U_dt
  COMPLEX*16,       DIMENSION(:,:), ALLOCATABLE :: dh2,dh3,U_AUX,Qubit_IDENTITY
  DOUBLE PRECISION, DIMENSION(:,:), ALLOCATABLE :: P_AVG,W2,W3
  DOUBLE PRECISION                              :: T1,T2,E_L,E_R

  DOUBLE PRECISION ::  m_ , eta,phi1,phi2,gamma,dt
  INTEGER          :: D_BARE

  ! ===================================================
  !PARAMETERS NEEDED TO DEFINE THE SPARSE MATRIX
  INTEGER,    DIMENSION(:), ALLOCATABLE :: ROW_INDEX,COLUMN
  COMPLEX*16, DIMENSION(:), ALLOCATABLE :: VALUES

  OPEN(UNIT=3,file="qubit_lattice_SP.dat", action="write")


  INFO = 0
  CALL FLOQUETINIT(ID,'qubit',INFO)
  D_BARE = ID%D_BARE

  ALLOCATE(dh2(D_BARE,D_BARE))
  ALLOCATE(dh3(D_BARE,D_BARE))
  ALLOCATE(W2(D_BARE,D_BARE))
  ALLOCATE(W3(D_BARE,D_BARE))
  ALLOCATE(P_AVG(D_BARE,D_BARE))
  ALLOCATE(U_AUX(D_BARE,D_BARE))
  ALLOCATE(U_dt(D_BARE,D_BARE))
  ALLOCATE(Qubit_IDENTITY(D_BARE,D_BARE))
  
  ALLOCATE(MODES_NUM(3))

  MODES_NUM(1) = 1 !(STATIC FIELD)
  MODES_NUM(2) = 1 !(DRIVING BY TWO HARMONICS)
  MODES_NUM(3) = 1 !(DRIVING BY A SECOND FREQUENCY)

  TOTAL_FREQUENCIES = SUM(MODES_NUM,1)
  ALLOCATE(FIELDS(TOTAL_FREQUENCIES))
  DO m=1,TOTAL_FREQUENCIES
     ALLOCATE(FIELDS(m)%V(ID%D_BARE,ID%D_BARE))
  END DO
  
  Qubit_IDENTITY = 0.0
  Qubit_IDENTITY(1,1) = 1.0
  Qubit_IDENTITY(2,2) = 1.0

  !eq. (20), arxiv 1612.02143
  m_    = 2.2
  eta   = 2.0
  phi1  = pi/10.0
  phi2  = 0.0
  gamma = 0.5*(1.0 + sqrt(5.0))

  FIELDS(1)%X     = 0.0
  FIELDS(1)%Y     = 0.0
  FIELDS(1)%Z     = 2.0*m_*eta
  FIELDS(1)%phi_x = 0.0
  FIELDS(1)%phi_y = 0.0
  FIELDS(1)%phi_z = 0.0
  FIELDS(1)%omega = 0.0
  FIELDS(1)%N_Floquet = 0

  FIELDS(2)%X     =  2.0*eta
  FIELDS(2)%Y     =  0.0
  FIELDS(2)%Z     = -2.0*eta
  FIELDS(2)%phi_x = phi1 - pi/2.0
  FIELDS(2)%phi_y = 0.0
  FIELDS(2)%phi_z = phi1 
  FIELDS(2)%omega = 0.1
  FIELDS(2)%N_Floquet = 6

  FIELDS(3)%X     =  0.0
  FIELDS(3)%Y     =  2.0*eta
  FIELDS(3)%Z     = -2.0*eta
  FIELDS(3)%phi_x = 0.0
  FIELDS(3)%phi_y = phi2 - pi/2
  FIELDS(3)%phi_z = phi2
  FIELDS(3)%omega = gamma*FIELDS(2)%OMEGA
  FIELDS(3)%N_Floquet = 5
 
  DO m=1,TOTAL_FREQUENCIES    
     FIELDS(m)%X = FIELDS(m)%X*exp(DCMPLX(0.0,1.0)*FIELDS(m)%phi_x)
     FIELDS(m)%Y = FIELDS(m)%Y*exp(DCMPLX(0.0,1.0)*FIELDS(m)%phi_y)
     FIELDS(m)%Z = FIELDS(m)%Z*exp(DCMPLX(0.0,1.0)*FIELDS(m)%phi_z)
  END DO

  D_MULTIFLOQUET = ID%D_BARE
  DO r=1,TOTAL_FREQUENCIES
     D_MULTIFLOQUET = D_MULTIFLOQUET*(2*FIELDS(r)%N_Floquet+1)
  END DO
  

  !=================================================================================
  !== MULTIMODE FLOQUET DRESSED BASIS AND TIME-EVOLUTION OPERATOR IN THE BARE BASIS
  !=================================================================================
  !WRITE(*,*) t2,ABS(U_AUX)**2

  CALL SETHAMILTONIANCOMPONENTS(ID,size(modes_num,1),total_frequencies,MODES_NUM,FIELDS,INFO)

  CALL MULTIMODEFLOQUETMATRIX_SP(ID,SIZE(MODES_NUM,1),total_frequencies,MODES_NUM,FIELDS,VALUES,ROW_INDEX,COLUMN,INFO)
!  WRITE(*,*) ROW_INDEX, SIZE(ROW_INDEX,1)
  WRITE(*,*) ALL(ROW_INDEX.GT.SIZE(ROW_INDEX,1),1)
!  WRITE(*,*) COLUMN, SIZE(COLUMN,1), SIZE(VALUES,1)
  WRITE(*,*) ALL(COLUMN.GT.330,1)
  E_L = -FIELDS(2)%N_FLOQUET*FIELDS(2)%OMEGA  - FIELDS(3)%N_FLOQUET*FIELDS(3)%OMEGA - FIELDS(1)%Z
  E_R = -E_L
  ALLOCATE(E_FLOQUET(D_MULTIFLOQUET))
  ALLOCATE(U_F(D_MULTIFLOQUET,D_MULTIFLOQUET))
  E_FLOQUET = 0.0
  U_F = 0.0
!  WRITE(*,*) D_MULTIFLOQUET,SIZE(VALUES,1),E_L,E_R,INFO,size(ROW_INDEX,1),SIZE(COLUMN,1)
  CALL MKLSPARSE_FULLEIGENVALUES(D_MULTIFLOQUET,SIZE(VALUES,1),VALUES,ROW_INDEX,COLUMN,E_L,E_R,E_FLOQUET,U_F,INFO)
    !--- EVALUATE THE AVERAGE TRANSITION PROBATILIBIES IN THE BARE BASIS
!!$  P_AVG = 0.0
!!$  CALL MULTIMODETRANSITIONAVG(SIZE(U_F,1),size(MODES_NUM,1),FIELDS,MODES_NUM,U_F,E_FLOQUET,ID%D_BARE,P_AVG,INFO)   
!!$  WRITE(*,*) FIELDS(2)%omega,P_AVG
!!$  
  !--- EVALUATE TIME-EVOLUTION OPERATOR IN THE BARE BASIS
  T1 = 0.0
  dt = 0.0001
  T2 = T1 + dt
  CALL MULTIMODETIMEEVOLUTINOPERATOR(SIZE(U_F,1),SIZE(MODES_NUM,1),MODES_NUM,U_F,E_FLOQUET,ID%D_BARE,FIELDS,T1,T2,U_dt,INFO) 
  U_AUX = Qubit_IDENTITY
  DO r=1,256
     dh2 = 2.0*eta*FIELDS(2)%OMEGA*(                 J_x*cos(fields(2)%omega*T2+phi1) + J_z*sin(fields(2)%omega*T2+phi1))*dt
     dh3 = 2.0*eta*FIELDS(3)%OMEGA*(DCMPLX(0.0,-1.0)*J_y*cos(fields(3)%omega*T2+phi2) + J_z*sin(fields(3)%omega*T2+phi2))*dt
     U_AUX = MATMUL(U_dt,U_AUX)
     W2 = W2 + MATMUL(TRANSPOSE(CONJG(U_AUX)),MATMUL(dh2,U_AUX))
     W3 = W3 + MATMUL(TRANSPOSE(CONJG(U_AUX)),MATMUL(dh3,U_AUX))     
     T2 = T2 + dt
     IF(MOD(r,10).EQ.0) WRITE(3,*) t2,ABS(U_AUX)**2,W2,W3
  END DO
  WRITE(3,*)
  WRITE(3,*)
  !DEALLOCATE(E_FLOQUET)
  !DEALLOCATE(U_F)

  T1 = 0.0
  dt = 0.0001
  T2 = 0.0
  W2 = 0.0
  W3 = 0.0
  DO r=1,256
     T2 = T2 + dt
     CALL MULTIMODETIMEEVOLUTINOPERATOR(SIZE(U_F,1),SIZE(MODES_NUM,1),MODES_NUM,U_F,E_FLOQUET,ID%D_BARE,FIELDS,T1,T2,U_AUX,INFO) 
     dh2 = 2.0*eta*FIELDS(2)%OMEGA*(                 J_x*cos(fields(2)%omega*T2+phi1) + J_z*sin(fields(2)%omega*T2+phi1))*dt
     dh3 = 2.0*eta*FIELDS(3)%OMEGA*(DCMPLX(0.0,-1.0)*J_y*cos(fields(3)%omega*T2+phi2) + J_z*sin(fields(3)%omega*T2+phi2))*dt
     W2 = W2 + MATMUL(TRANSPOSE(CONJG(U_AUX)),MATMUL(dh2,U_AUX))
     W3 = W3 + MATMUL(TRANSPOSE(CONJG(U_AUX)),MATMUL(dh3,U_AUX))     
     IF(MOD(r,10).EQ.0) WRITE(3,*) t2,ABS(U_AUX)**2,W2,W3
  END DO
  WRITE(3,*)
  DEALLOCATE(E_FLOQUET)
  DEALLOCATE(U_F)
  
  
END PROGRAM MULTIMODEFLOQUET
