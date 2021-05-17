// sitest.ks - Test sinfo script
// Copyright © 2021 V. Quetschke
// Version 0.1, 05/16/2021
@LAZYGLOBAL OFF.
RUNONCEPATH("libcommon").

SET TERMINAL:WIDTH TO 70.
SET TERMINAL:HEIGHT TO 45.
RUNPATH("sinfo"). // Get stage info
LOCAL loopTime IS TIME:SECONDS.
// Vessel info
LOCAL si TO stinfo().
// With "LOCAL si TO stinfo()."
// si[stage]:key the following keys are available:
// SMass .. startmass
// EMass .. endmass.
// DMass .. stagedmass.
// BMass .. fuel burned
// sTWR  .. start TWR
// eTWR  .. end TWR
// Ft    .. thrust
// ISPg  .. ISPg0
// dv    .. delta v
// dur   .. burn duration

PRINT " ".
IF si:TYPENAME() = "List" {
    PRINT "Succesfully received stage info!".
} ELSE {
    PRINT "sinfo.ks failed!".
    SET axx TO 1/0.
}

PRINT "Ship delta v: "+ROUND(SHIP:DELTAV:CURRENT,1).
PRINT "s:  SMass EMass DMass sTWR eTWR     Ft    ISP     dV   time".
FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
    PRINT s+":"+nuform(si[s]:SMass,3,3)+nuform(si[s]:EMass,3,2)
        +nuform(si[s]:DMass,3,2)+nuform(si[s]:sTWR,3,1)
        +nuform(si[s]:eTWR,3,1)+nuform(si[s]:Ft,5,1)
        +nuform(si[s]:ISPg,5,1)+" "+nuform(si[s]:dv,4,1)
        +" "+nuform(si[s]:dur,4,1).
}
PRINT "Runtime: "+ROUND((TIME:SECONDS-loopTime)*1000,1)+"ms".
