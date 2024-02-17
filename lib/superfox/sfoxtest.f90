program sfoxtest

! Generate and test possible waveforms for SuperFox signal.

  use wavhdr
  use sfox_mod
  use timer_module, only: timer
  use timer_impl, only: init_timer !, limtrace

  type(hdr) h                            !Header for .wav file
  integer*2 iwave(NMAX)                  !Generated i*2 waveform
  integer param(0:8)
  real*4 xnoise(NMAX)                    !Random noise
  real*4 dat(NMAX)                       !Generated real data
  complex cdat(NMAX)                     !Generated complex waveform
  complex clo(NMAX)                      !Complex Local Oscillator
  complex cnoise(NMAX)                   !Complex noise
  complex crcvd(NMAX)                    !Signal as received
  real a(3)
  real, allocatable :: s3(:,:)           !Symbol spectra: will be s3(NQ,NN)
  integer, allocatable :: msg0(:)        !Information symbols
  integer, allocatable :: parsym(:)      !Parity symbols
  integer, allocatable :: chansym0(:)    !Encoded data, 7-bit integers
  integer, allocatable :: chansym(:)     !Recovered hard-decision symbols
  integer, allocatable :: iera(:)        !Positions of erasures
  integer, allocatable :: rxdat(:)
  integer, allocatable :: rxprob(:)
  integer, allocatable :: rxdat2(:)
  integer, allocatable :: rxprob2(:)
  integer, allocatable :: correct(:)
  
  character fname*17,arg*12,itu*2

  nargs=iargc()
  if(nargs.ne.10) then
     print*,'Usage:   sfoxtest  f0   DT  ITU M  N  K  sw nv nfiles snr'
     print*,'Example: sfoxtest 1500 0.15  MM 8 74 44 100  0   10   -10'
     print*,'         f0=0 means f0, DT will assume suitable random values'
     print*,'         LQ: Low Latitude Quiet'
     print*,'         MM: Mid Latitude Moderate'
     print*,'         HD: High Latitude Disturbed'
     print*,'         ... and similarly for LM LD MQ MD HQ HM'
     print*,'         sw = width of Sync sweep, in Hz'
     print*,'         v=1 for .wav files, 2 for verbose output, 3 for both'
     print*,'         snr=0 means loop over SNRs 0 to -25 dB'
     go to 999
  endif
  call getarg(1,arg)
  read(arg,*) f0
  call getarg(2,arg)
  read(arg,*) xdt
  call getarg(3,itu)
  call getarg(4,arg)
  read(arg,*) mm0
  call getarg(5,arg)
  read(arg,*) nn0
  call getarg(6,arg)
  read(arg,*) kk0
  call getarg(7,arg)
  read(arg,*) syncwidth
  call getarg(8,arg)
  read(arg,*) nv
  call getarg(9,arg)
  read(arg,*) nfiles
  call getarg(10,arg)
  read(arg,*) snrdb

  call init_timer ('timer.out')
  call timer('sfoxtest',0)

  call sfox_init(mm0,nn0,kk0,itu,fspread,delay)
  baud=12000.0/NSPS
  tsym=1.0/baud
  bw=NQ*baud
  maxerr=(NN-KK)/2
  tsync=NSYNC/12000.0
  txt=(NN-2+NS)*NSPS/12000.0

  write(*,1000) MM,NN,KK,NSPS,baud,bw,itu,fspread,delay,maxerr,   &
       tsync,txt
1000 format('M:',i2,'   Base code: (',i3,',',i3,')   NSPS:',i5,   &
          '   Symbol Rate:',f7.3,'   BW:',f6.0/                   &
          'Channel: ',a2,'   fspread:',f4.1,'   delay:',f5.1,     &
          '   MaxErr:',i3,'  tsync:',f4.1,'   TxT:',f5.1/)

! Allocate storage for arrays that depend on code parameters.
  allocate(s3(0:NQ-1,0:NN-1))
  allocate(msg0(1:KK))
  allocate(parsym(1:NN-KK))
  allocate(chansym0(0:NN-1))
  allocate(chansym(0:NN-1))
  allocate(iera(0:NN-1))
  allocate(rxdat(0:NN-1))
  allocate(rxprob(0:NN-1))
  allocate(rxdat2(0:NN-1))
  allocate(rxprob2(0:NN-1))
  allocate(correct(0:NN-1))

  rms=100.
  fsample=12000.0                   !Sample rate (Hz)
  baud=12000.0/nsps                 !Keying rate, 11.719 baud for nsps=1024
  h=default_header(12000,NMAX)
  idummy=0
  bandwidth_ratio=2500.0/12000.0
  fgood0=1.0

! Generate a message
  msg0=0
  do i=1,KK
     msg0(i)=int(NQ*ran1(idummy))
  enddo

  call rs_init_sf(MM,NQ,NN,KK,NFZ)          !Initialize the Karn codec
  call rs_encode_sf(msg0,parsym)            !Compute parity symbols
  chansym0(0:kk-1)=msg0(1:kk)
  chansym0(kk:nn-1)=parsym(1:nn-kk)
!  chansym0=NQ/2  !### TEMPORARY, for SNR calibration ###

! Generate clo, the LO for sync detection
  call timer('clo     ',0)
  call sfox_clo(fsample,syncwidth,clo)
  call timer('clo     ',1)

! Generate cdat, the SuperFox waveform
  call timer('gen     ',0)
  call sfox_gen(chansym0,f0,fsample,syncwidth,cdat)
  call timer('gen     ',1)
  isnr0=-8

  do isnr=isnr0,-20,-1
     snr=isnr
     if(snrdb.ne.0.0) snr=snrdb
     sig=sqrt(2*bandwidth_ratio)*10.0**(0.05*snr)
     sigr=sqrt(2.)*sig
     if(snr.gt.90.0) sig=1.0
     ngoodsync=0
     ngood=0
     ntot=0
     nworst=0
     sqt=0.
     sqf=0.

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
           xdt=0.3*ran1(idummy)
           call timer('gen     ',0)
           call sfox_gen(chansym0,f1,fsample,syncwidth,cdat)
           call timer('gen     ',1)
        endif
        
        crcvd=0.
        crcvd(1:NMAX)=cshift(sig*cdat(1:NMAX),-nint(xdt*fsample)) + cnoise
        call timer('watterso',0)
        if(fspread.ne.0 .or. delay.ne.0) call watterson(crcvd,NMAX,NZ,fsample,&
             delay,fspread)
        call timer('watterso',1)

        dat=aimag(sigr*cdat(1:NMAX)) + xnoise     !Add generated AWGN noise
!        call plotspec(dat)     !### TEMPORARY, for SNR calibration ###
        fac=32767.0
        if(snr.ge.90.0) iwave(1:NMAX)=nint(fac*dat(1:NMAX))
        if(snr.lt.90.0) iwave(1:NMAX)=nint(rms*dat(1:NMAX))

! Find signal freq and DT
        call timer('sync    ',0)
        call sfox_sync(crcvd,clo,nv,f,t)
        call timer('sync    ',1)
        ferr=f-f1
        terr=t-xdt
        igoodsync=0
        if(abs(ferr).lt.baud/2.0 .and. abs(terr).lt.tsym/8.0) then
           igoodsync=1
           ngoodsync=ngoodsync+1
           sqt=sqt + terr*terr
           sqf=sqf + ferr*ferr
       endif

        a=0.
        a(1)=1500.0-f
        call timer('twkfreq ',0)
        call twkfreq(crcvd,crcvd,NMAX,12000.0,a)
        call timer('twkfreq ',1)
        f=1500.0
        call timer('demod   ',0)
        call sfox_demod(crcvd,f,t,s3,chansym)    !Get s3 and hard symbol values
        call timer('demod   ',1)

        call timer('prob    ',0)
        call sym_prob(s3,rxdat,rxprob,rxdat2,rxprob2)
        call timer('prob    ',1)

        nera=0
        chansym=mod(chansym,nq)                        !Enforce 0 to nq-1
        nharderr=count(chansym.ne.chansym0)            !Count hard errors
        ntot=ntot+nharderr
        nworst=max(nworst,nharderr)

!        call rs_decode_sf(rxdat,iera,nera,nfixed)    !Call the BM decoder
        ntrials=1000
        call timer('ftrsd3  ',0)
        call ftrsd3(s3,chansym0,rxdat,rxprob,rxdat2,rxprob2,ntrials,  &
             correct,param,ntry)
        call timer('ftrsd3  ',1)

        if(iand(nv,1).ne.0) then
           fname='000000_000001.wav'
           write(fname(8:13),'(i6.6)') ifile
           open(10,file=trim(fname),access='stream',status='unknown')
           write(10) h,iwave(1:NMAX)                !Save the .wav file
           close(10)
       endif

!        if(nharderr.le.maxerr) ngood=ngood+1
       if(count(correct.ne.chansym0).eq.0) ngood=ngood+1
     enddo  ! ifile
     fgoodsync=float(ngoodsync)/nfiles
     fgood=float(ngood)/nfiles
     if(isnr.eq.isnr0) write(*,1300)
1300 format('    SNR  iters fsync  fgood  averr  worst  rmsf  rmst'/  &
            '------------------------------------------------------')
     ave_harderr=float(ntot)/nfiles
     rmst=sqrt(sqt/ngoodsync)
     rmsf=sqrt(sqf/ngoodsync)
     write(*,1310) snr,nfiles,fgoodsync,fgood,ave_harderr,nworst,rmsf,rmst
1310 format(f7.2,i6,2f7.2,f7.1,i6,f7.2,f6.3)
     if(fgood.le.0.5 .and. fgood0.gt.0.5) then
        threshold=isnr + 1 - (fgood0-0.50)/(fgood0-fgood+0.000001)
     endif
     fgood0=fgood
     if(snrdb.ne.0.0) exit
!     if(fgood.eq.0.0) exit
     if(fgoodsync.lt.0.5) exit
  enddo  ! isnr
  if(snrdb.eq.0.0) write(*,1320) threshold
1320 format(/'Threshold sensitivity (50% decoding):',f6.1,' dB')
  call timer('sfoxtest',1)

999 call timer('sfoxtest',101)
end program sfoxtest

! include 'plotspec.f90'    !### TEMPORARY, for SNR calibration ###
