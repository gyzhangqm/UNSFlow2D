!------------------------------------------------------------------------------
! Main program of Cell-centroid finite volume flow solver 
!------------------------------------------------------------------------------
program main
use param
use grid
implicit none
integer(kind=i4)  :: i, j, irk,rk
real(kind=dp) :: c1(nvar), c2(nvar), c3(nvar),con(nvar)
real(kind=dp) :: cl, cd,dtbyarea,alfa
real(kind=sp) :: etime, elapsed(2), totaltime
real(kind=dp),allocatable:: ggqx(:,:),ggqy(:,:) 


!    Set some constants
call math

!    Read input parameters from file, also sets np, nt
call read_input

!    Read grid from file
call read_grid

!    Generating mesh connectivity 
call geometric

! Set initial condition
call initialize

!     Runge-Kutta time stepping
if(timemode=="rk3".and.cfl_max > 1.0d0) then
   print*,'CFL should be less than 1 for rk3 !!!'
   stop
elseif(timemode=="rk3".and.cfl_max < 1.0d0) then
print*,'RK3'
NIRK    = 5
allocate(airk(nirk),birk(nirk))
airk(1) = 0.0d0
airk(2) = 3.0d0/4.0d0
airk(3) = 1.0d0/3.0d0
birk(1) = 1.0d0
birk(2) = 1.0d0/4.0d0
birk(3) = 2.0d0/3.0d0
endif
!print*,'eps=',eps
!stop

iter = 0
fres = 1.0d0
call system('rm -f FLO.RES')
print*,'Beginning of iterations ...'
open(unit=99, file='FLO.RES')
do while(iter .lt. MAXITER .and. fres .gt. MINRES)

   iter = iter + 1
   cfl = 0.5d0*cfl_max*(1+dtanh(iter*7.d0/500.0 - 3.5))
   !cfl = 0.5d0*cfl_max*(1+dtanh(iter*10.d0/1000.0 - 5.0))
   call avg_c2v
   call time_step2
   !call time_step02
   call save_old

   !Gradient calculation using Green-Gauss
   !call Gradient_GG

   !Gradient calculation using diamond path reconstruction
   call Gradient_GG_FC

!   if (iter==500) then
!   allocate(ggqx(noc,nvar),ggqy(noc,nvar))
!   do i=1,noc 
!   ggqx(i,:)=cell(i)%qx(:) 
!   ggqy(i,:)=cell(i)%qy(:) 
!   enddo
!   call Gradient_GG_FC
!   do i=1,noc
!      write(10,201)i,(ggqx(i,j),j=1,nvar)
!      write(11,201)i,(ggqy(i,j),j=1,nvar)
!      write(12,201)i,(cell(i)%qx(j),j=1,nvar)
!      write(13,201)i,(cell(i)%qy(j),j=1,nvar)
!   enddo 
!   deallocate(ggqx,ggqy)
!   stop
!   201 format(1x,i8,1x,4(f16.8,2x))
!   endif

   if(timemode == 'rk3')then
      alfa=0.d0
      do irk=1,nirk
         call fvresidual
!         do i=1,noc
!            c1(:)=cell(i)%qold(:)
!            c2(:)=cell(i)%qc(:)
!            dtbyarea=cell(i)%dt/cell(i)%cv
!            do j=1,nvar
!               c3(j) = airk(irk)*c1(j) + &
!               birk(irk)*(c2(j)-dtbyarea*cell(i)%res(j))
!            enddo
!            cell(i)%qc(:)=c3(:)
!         enddo
       alfa=1.d0/dble(nirk-irk+1)     
       do i=1,noc
          dtbyarea=cell(i)%dt/cell(i)%cv
          do j=1,nvar
             cell(i)%qc(j)=cell(i)%qold(j)-alfa*dtbyarea*cell(i)%res(j)
          enddo
       enddo
      enddo
   elseif(timemode == 'lusgs')then
      call lusgs
   endif

   call residue
   write(99,'(i6,3e16.6)') iter, dlog10(fres),dlog10(fresi), cfl

   if(mod(iter,scrinterval) .eq. 0)then
      call tecplt 
      !call tecplt_del 
      call screen
   endif
enddo
close(99)

call tecplt 
call tecplt_del 


totaltime = etime(elapsed)
totaltime = totaltime/60.0
elapsed(1)= elapsed(1)/60.0
elapsed(2)= elapsed(1)/60.0
print *, 'Time: total=', totaltime, ' user=', elapsed(1), &
         ' system=', elapsed(2)

100 format(1x,i6,1x,4(f15.8,1x))



stop
end


subroutine screen
use param
use pri
use grid
implicit none
real(kind=dp) :: qc(nvar),con(nvar), cl, cd

integer(kind=i4)  :: is, i
real(kind=dp) :: q2, mach, ent 
 
pmin =  1.0d10
pmax = -1.0d10
mmin =  1.0d10
mmax = -1.0d10
rmin =  1.0d10
rmax = -1.0d10
umin =  1.0d10
umax = -1.0d10
vmin =  1.0d10
vmax = -1.0d10
emin =  1.0d10
emax = -1.0d10
do is=1,noc
    con(:)=cell(is)%qc(:)
    call con2prim(con)
    q2   = u*u  + v*v 
    rmin =dmin1(rmin, rho) 
    rmax =dmax1(rmax, rho) 
    umin =dmin1(umin, u) 
    umax =dmax1(umax, u) 
    vmin =dmin1(vmin, v) 
    vmax =dmax1(vmax, v) 
    pmin =dmin1(pmin, p) 
    pmax =dmax1(pmax, p) 
    mach =dsqrt(q2*rho/(GAMMA*p))
    mmin =dmin1(mmin, mach)
    mmax =dmax1(mmax, mach)
    ent  =dlog10(p/rho**GAMMA/ent_inf)
    emin =dmin1(emin, ent)
    emax =dmax1(emax, ent)
enddo

100 format(1x,i6,1x,4(f15.6,1x))
write(*,9)('-',i=1,70)
9     format(70a)
write(*,10)m_inf,aoa_deg,Rey,CFL
10    format(' Mach =',f6.3,'    AOA =',f6.2, '  Rey = ',e15.4, &
       '   CFL = ',e15.4)
write(*,11)flux_type,ilimit,gridfile
11    format(' Flux = ',a7, '  Lim = ',i2,'     Grid= ',a30)
write(*,9)('-',i=1,70)
write(*,'(" Iterations        =",i12)')iter
write(*,'(" Global dt         =",e16.6)') dtglobal
write(*,'(" L2 residue        =",e16.6)')fres
write(*,'(" Linf residue      =",e16.6)')fresi
write(*,'(" Linf cell         =",i12)') iresi
write(*,*)
!write(*,'(" Cl, Cd            =",2f12.6)')cl,cd
write(*,*)
write(*,'(27x,"Min",8x,"Max")')          
write(*,'(" Density           =",2f12.6)')rmin, rmax
write(*,'(" Pressure          =",2f12.6)')pmin, pmax
write(*,'(" Mach number       =",2f12.6)')mmin, mmax
write(*,'(" x velocity        =",2f12.6)')umin, umax
write(*,'(" y velocity        =",2f12.6)')vmin, vmax
write(*,'(" Entropy           =",2f12.6)')emin, emax
write(*,*)
write(*,*)
write(*,*)
write(*,*)
call flush(6)

end


SUBROUTINE tecplt
use param
use grid
implicit none
integer(kind=i4) :: i,j,c, funit
real(kind=dp) :: con(nvar),qc(nvar)
real(kind=dp) :: q2, mach,entropy,mul,mutot,sutherland
real(kind=dp) :: ro , uo,vo,po,wt,x1,x2,y1,y2

funit = 5
call avg_c2v

OPEN(funit,file='tecplt.dat')
WRITE(funit,*) 'TITLE = "flo2d output" '

!WRITE(funit,*) 'VARIABLES="X","Y","rho","u","v","p" '
WRITE(funit,*) 'VARIABLES="X","Y","rho","u","v","p","M"'
WRITE(funit,*) 'ZONE F=FEPOINT,ET=quadrilateral'
WRITE(funit,*) 'N=',nop,',E=',noc
do i=1,nop

    ro=pt(i)%prim(1)
    uo=pt(i)%prim(2)
    vo=pt(i)%prim(3)
    po=pt(i)%prim(4)

    q2   = uo**2 + vo**2
    mach = dsqrt(q2*ro/(GAMMA*po))
    entropy=log10(po/ro**GAMMA/ent_inf)

    !WRITE(funit,*)pt(i)%x,pt(i)%y,r,u,v,p,mach
    WRITE(funit,100)pt(i)%x,pt(i)%y,ro,uo,vo,po,mach
      
END DO
DO i=1,noc
   !WRITE(funit,*)elem(1,i), elem(2,i), elem(3,i) 
   WRITE(funit,*)(cell(i)%c2v(j),j=1,cell(i)%nc2v-1) 
END DO

CLOSE(funit)

DO i=1,noc
   do j=1,cell(i)%nc2v-1
      c=cell(i)%c2v(j)
      x2 = pt(c)%x ; y2 = pt(c)%y
      write(34,*)x2,y2
   END DO
      x1 = pt(cell(i)%c2v(1))%x ; y1 = pt(cell(i)%c2v(1))%y
      write(34,*)x1,y1
      write(34,*)
END DO

100 format(1x,7(f15.6,2x))


END SUBROUTINE


SUBROUTINE tecplt_del
use param
use grid
implicit none
integer(kind=i4) :: i,j,c, funit
real(kind=dp) :: con(nvar),qc(nvar)
real(kind=dp) :: q2, mach,entropy,mul,mutot,sutherland
real(kind=dp) :: ro , uo,vo,po,wt,x1,x2,y1,y2

funit = 5
call avg_Grad_c2v

OPEN(funit,file='tecplt_del.dat')
WRITE(funit,*) 'TITLE = "flo2d derivatives" '
WRITE(funit,*)'VARIABLES="X","Y","rhodx","rhody","udx","udy","vdx","vdy","pdx","pdy"'
WRITE(funit,*) 'ZONE F=FEPOINT,ET=quadrilateral'
WRITE(funit,*) 'N=',nop,',E=',noc
do i=1,nop
    WRITE(funit,100)pt(i)%x,pt(i)%y,pt(i)%dx(1),pt(i)%dy(1),pt(i)%dx(2),pt(i)%dy(2),pt(i)%dx(3),pt(i)%dy(3),pt(i)%dx(4),pt(i)%dy(4)
END DO
DO i=1,noc
   !WRITE(funit,*)elem(1,i), elem(2,i), elem(3,i) 
   WRITE(funit,*)(cell(i)%c2v(j),j=1,cell(i)%nc2v-1) 
END DO

CLOSE(funit)

DO i=1,noc
   do j=1,cell(i)%nc2v-1
      c=cell(i)%c2v(j)
      x2 = pt(c)%x ; y2 = pt(c)%y
      write(34,*)x2,y2
   END DO
      x1 = pt(cell(i)%c2v(1))%x ; y1 = pt(cell(i)%c2v(1))%y
      write(34,*)x1,y1
      write(34,*)
END DO

100 format(1x,7(f15.6,2x))


END SUBROUTINE


function dotprod(n1,n2,xc,yc)
   use grid
   implicit none
   integer(kind=i4):: n1,n2
   real(kind=dp)   :: x1,y1,x2,y2
   real(kind=dp)   :: dx,dy,ds,xc,yc
   real(kind=dp)   :: dotprod,nx,ny,rx,ry


   x1 = pt(n1)%x ; y1 = pt(n1)%y
   x2 = pt(n2)%x ; y2 = pt(n2)%y
   dx = x2-x1 ; dy = y2-y1
   ds = dsqrt(dx*dx+dy*dy)
   nx = dy/ds ; ny = -dx/ds

   dx = xc-x1 ; dy = yc-y1
   ds = dsqrt(dx*dx+dy*dy)
   rx = dx/ds
   ry = dy/ds
   dotprod = rx*nx+ry*ny

end function dotprod


function crossprod(n1,n2,m1,m2)
   use grid
   implicit none
   integer(kind=i4):: n1,n2,m1,m2
   real(kind=dp)   :: x1,y1,x2,y2
   real(kind=dp)   :: x3,y3,x4,y4
   real(kind=dp)   :: dx,dy,ds
   real(kind=dp)   :: crossprod,nx,ny,rx,ry


   x1 = pt(n1)%x ; y1 = pt(n1)%y
   x2 = pt(n2)%x ; y2 = pt(n2)%y

   x3 = pt(m1)%x ; y3 = pt(m1)%y
   x4 = pt(m2)%x ; y4 = pt(m2)%y

   dx = x2-x1 ; dy = y2-y1
   ds = dsqrt(dx*dx+dy*dy)
   nx = dy/ds ; ny = -dx/ds

   dx = x4-x3 ; dy = y4-y3
   ds = dsqrt(dx*dx+dy*dy)
   rx = dx/ds
   ry = dy/ds

   crossprod = nx*ry-ny*rx

end function crossprod
