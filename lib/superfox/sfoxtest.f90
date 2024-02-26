program sfoxtest

! Generate and test possible waveforms for SuperFox signal.

  use wavhdr
  use sfox_mod
  use timer_module, only: timer
  use timer_impl, only: init_timer !, limtrace

  type(hdr) h                            !Header for .wav file
  integer*2 iwave(NMAX)                  !Generated i*2 waveform
  integer param(0:8)
  integer isync(44)
  integer jsync(171)
  integer itone(171)
  integer nsb(10)
  real*4 xnoise(NMAX)                    !Random noise
  real*4 dat(NMAX)                       !Generated real data
  complex cdat(NMAX)                     !Generated complex waveform
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
  logical hard_sync
  character fname*17,arg*12,itu*2

  data isync/ 1,   2,   5,  11,  19,  24,  26,  28,  29,  35,  &
             39,  48,  51,  53,  55,  56,  66,  71,  74,  78,  &
             80,  82,  84,  85,  92,  98, 103, 107, 109, 111,  &
            116, 122, 130, 131, 134, 136, 137, 140, 146, 154,  &
            159, 161, 163, 165/

  data nsb/1,2,4,7,11,16,22,29,37,39/

  nargs=iargc()
  if(nargs.ne.11) then
     print*,'Usage:   sfoxtest  f0   DT  ITU M  N   K NS v hs nfiles snr'
     print*,'Example: sfoxtest 1500 0.15  MM 7 127 48 33 0  F   10   -10'
     print*,'         f0=0 means f0, DT will assume suitable random values'
     print*,'         LQ: Low Latitude Quiet'
     print*,'         MM: Mid Latitude Moderate'
     print*,'         HD: High Latitude Disturbed'
     print*,'         ... and similarly for LM LD MQ MD HQ HM'
     print*,'         NS: number of sync symbols'
     print*,'         v=1 for .wav files, 2 for verbose output, 3 for both'
     print*,'         hs = T for hard-wired sync'
     print*,'         snr=0 means loop over SNRs'
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
  read(arg,*) ns0
  call getarg(8,arg)
  read(arg,*) nv
  call getarg(9,arg)
  hard_sync=arg(1:1).eq.'T'
  call getarg(10,arg)
  read(arg,*) nfiles
  call getarg(11,arg)
  read(arg,*) snrdb

  call init_timer ('timer.out')
  call timer('sfoxtest',0)

  fsample=12000.0                   !Sample rate (Hz)
  call sfox_init(mm0,nn0,kk0,itu,fspread,delay,fsample,ns0)
  tsync=NSYNC/fsample
  txt=(NN+NS)*NSPS/fsample
  nstype=nv/10
  nv=mod(nv,10)

  write(*,1000) MM,NN,KK,NSPS,baud,bw,itu,tsync,txt,nstype
1000 format('M:',i2,'   Base code: (',i3,',',i3,')   NSPS:',i5,   &
          '   Baud:',f7.3,'   BW:',f9.3/                   &
          'Channel: ',a2,'   Tsync:',f4.1,'   TxT:',f5.1,'   SyncType:',i2/)

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

  idum=-1
  if(nstype.eq.2) then
     jsync=0
     jsync(1)=1
     jsync(NDS)=1
     ms=2
     do i=1,100000
        j=1 + (NDS-1)*ran1(idum)
        if(jsync(j).eq.0) then
           jsync(j)=1
           ms=ms+1
           if(ms.eq.NS) exit
        endif
     enddo
     j=0
     do i=1,NDS
        if(jsync(i).eq.1) then
           j=j+1
           isync(j)=i
        endif
     enddo
  else if(nstype.eq.3) then
     isync(1:10)=nsb
     isync(11:20)=nsb + isync(10) + 2
     isync(21:30)=nsb + isync(20) + 2
     isync(31:40)=nsb + isync(30) + 2
     isync(41:44)=nsb(1:4) + isync(40) + 2
  endif

  rms=100.
  baud=fsample/nsps                 !Keying rate, 11.719 baud for nsps=1024
  bandwidth_ratio=2500.0/fsample
  fgood0=1.0

! Generate a message
  msg0=0
  do i=1,KK
     msg0(i)=int(NQ*ran1(idum))
  enddo

  call rs_init_sf(MM,NQ,NN,KK,NFZ)          !Initialize the Karn codec
  call rs_encode_sf(msg0,parsym)            !Compute parity symbols
  chansym0(0:kk-1)=msg0(1:kk)
  chansym0(kk:nn-1)=parsym(1:nn-kk)

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
           f1=1500.0 + 20.0*(ran1(idum)-0.5)
           xdt=ran1(idum)-0.5
        endif
        call timer('gen     ',0)
! Generate cdat, the SuperFox waveform
        call sfox_gen(chansym0,f1,fsample,isync,itone,cdat)
        call timer('gen     ',1)

        crcvd=0.
        crcvd(1:NMAX)=cshift(cdat(1:NMAX),-nint((0.5+xdt)*fsample))
        call timer('watterso',0)
        if(fspread.ne.0 .or. delay.ne.0) call watterson(crcvd,NMAX,NZ,fsample,&
             delay,fspread)
        call timer('watterso',1)

        dat=aimag(sigr*crcvd(1:NMAX)) + xnoise    !Add generated AWGN noise
        fac=32767.0
        if(snr.ge.90.0) iwave(1:NMAX)=nint(fac*dat(1:NMAX))
        if(snr.lt.90.0) iwave(1:NMAX)=nint(rms*dat(1:NMAX))

        crcvd=sig*crcvd+cnoise
        if(hard_sync) then
           f=f1  ! + 5.0*(ran1(idum)-0.5)
           t=xdt ! + 0.01*(ran1(idum)-0.5)
        else
! Find signal freq and DT
           call timer('sync    ',0)
           call sfox_sync(iwave,fsample,isync,f,t)
           call timer('sync    ',1)
        endif
        ferr=f-f1
        terr=t-xdt
!        write(*,4100) f1,f,ferr,xdt,t,terr
!4100    format(3f10.1,3f10.3)

        igoodsync=0
        if(abs(ferr).lt.baud/2.0 .and. abs(terr).lt.tsym/4.0) then
           igoodsync=1
           ngoodsync=ngoodsync+1
           sqt=sqt + terr*terr
           sqf=sqf + ferr*ferr
        endif

        a=0.
        a(1)=1500.0-f
        call timer('twkfreq ',0)
        call twkfreq(crcvd,crcvd,NMAX,fsample,a)
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

        ntrials=1000
        call timer('ftrsd3  ',0)
        call ftrsd3(s3,chansym0,rxdat,rxprob,rxdat2,rxprob2,ntrials,  &
             correct,param,ntry)
        call timer('ftrsd3  ',1)

        if(iand(nv,1).ne.0) then
           h=default_header(12000,NMAX)
           fname='000000_000001.wav'
           write(fname(8:13),'(i6.6)') ifile
           open(10,file=trim(fname),access='stream',status='unknown')
           write(10) h,iwave(1:NMAX)                !Save the .wav file
           close(10)
       endif

       if(count(correct.ne.chansym0).eq.0) ngood=ngood+1
     enddo  ! ifile
     fgoodsync=float(ngoodsync)/nfiles
     fgood=float(ngood)/nfiles
     if(isnr.eq.isnr0) write(*,1300)
1300 format('    SNR  Eb/No  iters fsync  fgood  averr   rmsf   rmst'/  &
            '-------------------------------------------------------')
     ave_harderr=float(ntot)/nfiles
     rmst=sqrt(sqt/ngoodsync)
     rmsf=sqrt(sqf/ngoodsync)
     ebno=snr-10*log10(baud/2500*mm0*KK/NN)
     write(*,1310) snr,ebno,nfiles,fgoodsync,fgood,ave_harderr,rmsf,rmst
1310 format(f7.2,f7.2 i6,2f7.4,f7.1,f7.2,f7.4)
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

