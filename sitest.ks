// sitest.ks - Test sinfo script
// Copyright © 2021 V. Quetschke
// Version 0.2, 07/18/2021
@LAZYGLOBAL OFF.
RUNONCEPATH("libcommon").

SET TERMINAL:WIDTH TO 76.
SET TERMINAL:HEIGHT TO 45.

// Run it at full speed!
SET CONFIG:IPU TO 2000.

RUNONCEPATH("etree7"). // Get stage info

LOCAL loopTime IS TIME:SECONDS.

// Vessel info
LOCAL si TO stinfo(1). // At sea level.
//  si[stage]:key with the following defined keys values:
//   SMass   .. startmass
//   EMass   .. endmass.
//   DMass   .. stagedmass.
//   BMass   .. fuel burned
//   sTWR    .. start TWR
//   maxTWR  .. max TWR
//   sSLT    .. start SLT (Sea level thrust)
//   maxSLT  .. max SLT
//   FtV     .. thrust in vacuum
//   FtA     .. thrust at current position
//   KSPispV .. ISPg0 KSP - vacuum
//   KERispV .. ISPg0 Kerbal Engineer Redux - vacuum
//   KSPispA .. ISPg0 KSP - at atmospheric pressure
//   KERispA .. ISPg0 Kerbal Engineer Redux - at atmospheric pressure
//   VdV     .. Vacuum delta V
//   AdV     .. Atmospheric delta V (see atmo parameter)
//   dur     .. burn duration
// The following key is the same for all stages:
//   ATMO    .. Atmospheric pressure used for thrust calculation

PRINT " ".
IF si:TYPENAME() = "List" {
    PRINT "Succesfully received stage info!".
} ELSE {
    PRINT "sinfo.ks failed!".
    SET axx TO 1/0.
}

PRINT "Ship vacuum delta v:  "+ROUND(SHIP:DELTAV:VACUUM,1)+"   Atmospheric pressure: "+si[0]:ATMO.
PRINT "Ship current delta v: "+ROUND(SHIP:DELTAV:CURRENT,1)+"   ASL delta v: "+ROUND(SHIP:DELTAV:ASL,1).
PRINT "s:  SMass EMass DMass BMass  sTWR maTWR KSPispV KERispV    VdV KSP dV   time".
FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
    PRINT s+":"+nuform(si[s]:SMass,3,3)+nuform(si[s]:EMass,3,2)
        +nuform(si[s]:DMass,3,2)+nuform(si[s]:BMass,3,2)+nuform(si[s]:sTWR,3,2)
        +nuform(si[s]:maxTWR,3,2)+nuform(si[s]:KSPispV,5,2)
        +nuform(si[s]:KERispV,5,2)+" "+nuform(si[s]:VdV,4,1)
        +" "+nuform(SHIP:STAGEDELTAV(s):VACUUM,4,1)+" "+nuform(si[s]:dur,4,1).
}
PRINT " ".
PRINT "s:    FtV    FtA  sSLT maSLT KSPispA KERispA    AdV KSP ASL dV KSP Cur dV".
FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
    PRINT s+":"+nuform(si[s]:FtV,5,1)+nuform(si[s]:FtA,5,1)
        +nuform(si[s]:sSLT,3,2)+nuform(si[s]:maxSLT,3,2)
        +nuform(si[s]:KSPispA,5,2)+nuform(si[s]:KERispA,5,2)
        +" "+nuform(si[s]:AdV,4,1)
        +" "+nuform(SHIP:STAGEDELTAV(s):ASL,8,1)+" "+nuform(SHIP:STAGEDELTAV(s):CURRENT,8,1).
}
PRINT "Runtime: "+ROUND((TIME:SECONDS-loopTime)*1000,1)+"ms".
