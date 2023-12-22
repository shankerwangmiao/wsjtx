subroutine qmapa(dd,ss,savg,newdat,nutc,fcenter,ntol,nfa,nfb,         &
     mousedf,mousefqso,nagain,nfshift,max_drift,offset,nfcal,mycall,  &
     hiscall,hisgrid,nfsample,nBaseSubmode,ndepth,datetime,ndop00,    &
     fselected,bAlso30,nhsym,nCFOM)

!  Processes timf2 data received from Linrad to find and decode Q65 signals.

  use timer_module, only: timer

  type candidate
     real :: snr          !Relative S/N of sync detection
     real :: f            !Freq of sync tone, 0 to 96000 Hz
     real :: xdt          !DT of matching sync pattern, -1.0 to +4.0 s
     integer :: ntrperiod !60 for Q65-60x, 30 for Q65-30x
     integer :: iseq      !0 for first half-minute, 1 for second half
  end type candidate

  parameter (NFFT=32768)             !Size of FFTs done in symspec()
  parameter (MAX_CANDIDATES=50)
  parameter (MAXMSG=1000)            !Size of decoded message list
  parameter (NSMAX=60*96000)
  complex cx(NSMAX/64)               !Data at 1378.125 samples/s
  real dd(2,NSMAX)                   !I/Q data from Linrad
  real ss(400,NFFT)                  !Symbol spectra
  real savg(NFFT)                    !Average spectrum
  real*8 fcenter                     !Center RF frequency, MHz
  logical*1 bAlso30,bClickDecode
  character mycall*12,hiscall*12,hisgrid*6
  type(candidate) :: cand(MAX_CANDIDATES)
  character*60 result
  character*20 datetime
  common/decodes/ndecodes,ncand,nQDecoderDone,nWDecoderBusy,              &
       nWTransmitting,result(50)
  save

  tsec0=sec_midn()
  if(nagain.eq.1) ndepth=3            !Use full depth for click-to-decode
  nkhz_center=nint(1000.0*(fcenter-int(fcenter)))
  mfa=nfa-nkhz_center+48
  mfb=nfb-nkhz_center+48
  mode_q65=nBaseSubmode
  nts_q65=2**(mode_q65-1)             !Q65 tone separation factor
  f0_selected=fselected - nkhz_center + 48.0

  call timer('get_cand',0)
! Get a list of decoding candidates
  call getcand2(ss,savg,nts_q65,nagain,ntol,f0_selected,bAlso30,cand,ncand)
  call timer('get_cand',1)

  nwrite_q65=0
  df=96000.0/NFFT                     !df = 96000/NFFT = 2.930 Hz
  ftol=0.010                          !Frequency tolerance (kHz)
  foffset=0.001*(1270 + nfcal)        !Offset from sync tone, plus CAL
  fqso=mousefqso + foffset - 0.5*(nfa+nfb) + nfshift !fqso at baseband (khz)
  nqd=0
  bClickDecode=(nagain.eq.1)
  nagain2=0

  call timer('filbig  ',0)
  call filbig(dd,NSMAX,f0,newdat,nfsample,cx,n5) !Do the full-length FFT
  call timer('filbig  ',1)

  do icand=1,ncand                        !Attempt to decode each candidate
     f0=cand(icand)%f
     ntrperiod=cand(icand)%ntrperiod
     iseq=cand(icand)%iseq
     mode_q65_tmp=mode_q65
     if(ntrperiod.eq.30) mode_q65_tmp=max(1,mode_q65-1)
     freq=f0+nkhz_center-48.0-1.27046
     ikhz=nint(freq)
     idec=-1
     call timer('q65b    ',0)
     call q65b(nutc,nqd,fcenter,nfcal,nfsample,ikhz,mousedf,ntol,           &
          ntrperiod,iseq,mycall,hiscall,hisgrid,mode_q65_tmp,f0,fqso,       &
          nkhz_center,newdat,nagain2,bClickDecode,max_drift,offset,         &
          ndepth,datetime,nCFOM,ndop00,idec)
     call timer('q65b    ',1)
     tsec=sec_midn() - tsec0
! Don't start another decode attempt if it's too late...
     if(nhsym.eq.330 .and. tsec.gt.6.0) exit
     if(tsec.gt.16.0) exit
     if(bClickDecode .and. idec.ge.0) exit
  enddo  ! icand

  return
end subroutine qmapa
