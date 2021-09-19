// LauTarget.ks - Launch into orbit with inclination and LAN from selected target.
// Copyright © 2021 V. Quetschke
// Version 0.3, 09/19/2021
@LAZYGLOBAL OFF.

// Parameters
DECLARE PARAMETER targetAltkm is 80.

// Abort if no target is set.
IF NOT HASTARGET {
    PRINT " ".
    PRINT "No target set! Select a target before running the script.".
    PRINT " ".
    PRINT 1/0.
}

LOCAL targetIncl TO TARGET:OBT:INCLINATION. // Inclination of target.
LOCAL lauLAN TO TARGET:OBT:LAN.   // LAN of target

PRINT " ".
PRINT "Target information".
PRINT "Target: "+TARGET.
PRINT "Orbiting: "+TARGET:BODY.
PRINT "Inclination: "+ROUND(targetIncl,1).
PRINT "LAN: "+ROUND(lauLAN,1).
PRINT " ".
PRINT "Executing LauLAN ...".
PRINT "3".
WAIT 1. 
PRINT "2".
WAIT 1. 
PRINT "1".
WAIT 1. 

RUNPATH("LauLAN",targetAltkm,targetIncl,lauLAN).
