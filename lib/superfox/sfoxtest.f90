program sfoxtest

! Generate and test sync waveforms for possible use in SuperFox signal.

  use wavhdr
  use sfox_mod
!  include "sfox_params.f90"
  type(hdr) h                            !Header for .wav file
  integer*2 iwave(NMAX)                  !Generated i*2 waveform
  real*4 xnoise(NMAX)                    !Random noise
  real*4 dat(NMAX)                       !Generated real data
  complex cdat(NMAX)                     !Generated complex waveform
  complex clo(NMAX)                      !Complex Local Oscillator
  complex cnoise(NMAX)                   !Complex noise
  complex crcvd(NMAX)                    !Signal as received
  real a(3)

  integer, allocatable :: msg0(:)        !Information symbols
  integer, allocatable :: parsym(:)      !Parity symbols
  integer, allocatable :: chansym0(:)    !Encoded data, 7-bit integers
  integer, allocatable :: chansym(:)     !Recovered hard-decision symbols
  integer, allocatable :: iera(:)        !Positions of erasures
  character fname*17,arg*12

  nargs=iargc()
  if(nargs.ne.9) then
     print*,'Usage:   sfoxtest  f0   DT fspread delay M  N  K nfiles snr'
     print*,'Example: sfoxtest 1500 0.15   0.5   1.0  8 74 44  10   -10'
     go to 999
  endif
  call getarg(1,arg)
  read(arg,*) f0
  call getarg(2,arg)
  read(arg,*) xdt
  call getarg(3,arg)
  read(arg,*) fspread
  call getarg(4,arg)
  read(arg,*) delay
  call getarg(5,arg)
  read(arg,*) mm0
  call getarg(6,arg)
  read(arg,*) nn0
  call getarg(7,arg)
  read(arg,*) kk0
  call getarg(8,arg)
  read(arg,*) nfiles
  call getarg(9,arg)
  read(arg,*) snrdb

  call sfox_init(mm0,nn0,kk0)
  syncwidth=100.0
  baud=12000.0/NSPS
  bw=NQ*baud
  
  write(*,1000) MM,NN,KK,NSPS,baud,bw
1000 format('M:',i2,'   Base code: (',i3,',',i3,')   NSPS:',i5,   &
          '   Symbol Rate:',f7.3,'   BW:',f6.0)
  
  allocate(msg0(1:KK))
  allocate(parsym(1:NN-KK))
  allocate(chansym0(1:NN))
  allocate(chansym(1:NN))
  allocate(iera(1:NN))

  rms=100.
  fsample=12000.0                   !Sample rate (Hz)
  baud=12000.0/nsps                 !Keying rate, 11.719 baud for nsps=1024
  h=default_header(12000,NMAX)
  idummy=0
  bandwidth_ratio=2500.0/6000.0

! Generate a message
  msg0=0
  do i=1,KK-2
     msg0(i)=i
  enddo
! Append a CRC here ...

  call rs_init_sf(MM,NQ,NN,KK,NFZ)          !Initialize the Karn codec
  call rs_encode_sf(msg0,parsym)            !Compute parity symbols
  chansym0(1:kk)=msg0(1:kk)
  chansym0(kk+1:nn)=parsym(1:nn-kk)

! Generate cdat (SuperFox waveform) and clo (LO for sync detection)
  call gen_sfox(chansym0,f0,fsample,syncwidth,cdat,clo)

  do isnr=0,-20,-1
     snr=isnr
     if(snrdb.ne.0.0) snr=snrdb
     sig=sqrt(2*bandwidth_ratio)*10.0**(0.05*snr)
     if(snr.gt.90.0) sig=1.0
     ngoodsync=0
     ngood=0
     ntot=0
     nworst=0

     do ifile=1,nfiles
        xnoise=0.
        cnoise=0.
        if(snr.lt.90) then
           do i=1,NMAX                     !Generate Gaussian noise
              x=gran()
              y=gran()
              xnoise(i)=x
              cnoise(i)=cmplx(x,y)
           enddo
        endif

        f1=f0
        if(f0.eq.0.0) then
           f1=1500.0 + 200.0*(ran1(idummy)-0.5)
           xdt=2.0*(ran1(idummy)-0.5)
           call gen_sfox(chansym0,f1,fsample,syncwidth,cdat,clo)
        endif
        
        crcvd=0.
        crcvd(1:NMAX)=cshift(sig*cdat(1:NMAX),-nint(xdt*fsample)) + cnoise

        dat=aimag(sig*cdat(1:NMAX)) + xnoise     !Add generated AWGN noise
        fac=32767.0
        if(snr.ge.90.0) iwave(1:NMAX)=nint(fac*dat(1:NMAX))
        if(snr.lt.90.0) iwave(1:NMAX)=nint(rms*dat(1:NMAX))

        if(fspread.ne.0 .or. delay.ne.0) call watterson(crcvd,NMAX,NZ,fsample,&
             delay,fspread)

! Find signal freq and DT
        call sync_sf(crcvd,clo,snrdb,f,t)
        ferr=f-f1
        terr=t-xdt
        if(abs(ferr).lt.3.0 .and. abs(terr).lt.0.01) ngoodsync=ngoodsync+1
!        if(abs(terr).lt.0.01) ngoodsync=ngoodsync+1

        a=0.
        a(1)=1500.0-f
        call twkfreq(crcvd,crcvd,NMAX,12000.0,a)
        f=1500.0
        call hard_symbols(crcvd,f,t,chansym)           !Get hard symbol values
        nera=0
        chansym=mod(chansym,nq)                        !Enforce 0 to nq-1
        nharderr=count(chansym.ne.chansym0)            !Count hard errors
!        write(71,3071) f1,f,ferr,xdt,t,terr,nharderr
!3071    format(6f10.3,i6)
        ntot=ntot+nharderr
        nworst=max(nworst,nharderr)
        call rs_decode_sf(chansym,iera,nera,nfixed)    !Call the decoder
  
        if(snrdb.ne.0) then
           fname='000000_000001.wav'
           write(fname(8:13),'(i6.6)') ifile
           open(10,file=trim(fname),access='stream',status='unknown')
           write(10) h,iwave(1:NMAX)                !Save the .wav file
           close(10)
           write(*,1100) f1,xdt
1100       format(/'f0:',f7.1,'  xdt:',f6.2)
           write(*,1112) f,t
1112       format('f: ',f7.1,'   DT:',f6.2)
           write(*,1110) ferr,terr
1110       format('err:',f6.1,f12.2)
           write(*,1120) nharderr
1120       format('Hard errors:',i4)
        endif

        maxerr=(nn-kk)/2
        if(nharderr.le.maxerr) ngood=ngood+1
!        write(13,1200) ifile,snr,ferr,terr,nharderr
!1200    format(i5,3f10.3,i5)
     enddo  ! ifile
!     print*,'D'
     fgoodsync=float(ngoodsync)/nfiles
     fgood=float(ngood)/nfiles
     if(isnr.eq.0) write(*,1300)
1300 format('    SNR     N  fsync  fgood  averr  worst'/  &
            '-----------------------------------------')
     ave_harderr=float(ntot)/nfiles
     write(*,1310) snr,nfiles,fgoodsync,fgood,ave_harderr,nworst
1310 format(f7.2,i6,2f7.2,f7.1,i6)
     if(snrdb.ne.0.0) exit
     if(fgoodsync.lt.0.5) exit
  enddo  ! isnr

999 end program sfoxtest
