// CircAtAP.ks - Create node to circularize at AP script
// Copyright © 2021 V. Quetschke
// Version 0.2, 09/19/2021

@LAZYGLOBAL OFF.
CLEARSCREEN.

//display info
PRINT "Calculate maneuver node".
PRINT "Apoapsis: "+round(apoapsis)+" m".
PRINT "Periapsis: "+round(periapsis)+" m".
PRINT "Time to apoapsis: "+round(eta:apoapsis)+"s".
PRINT "Running: CircAtAp".
PRINT " ".

LOCAL TargetV to ((body:mu)/(body:radius+apoapsis))^0.5. // Orbital speed at target altitude (apoapsis)
LOCAL ApoapsisV to (body:mu*((2/(body:radius+apoapsis))-(1/orbit:semimajoraxis)))^0.5. // Actual speed at AP
LOCAL BurnDeltaV to TargetV-ApoapsisV. // How much faster do we need to go to acive a cirular orbit

// Crude burn duration estimate
LOCAL burnDuration to (BurnDeltaV*mass)/availablethrust.

// Add the node
LOCAL myNode to NODE( TIME:SECONDS+eta:apoapsis, 0, 0, BurnDeltaV ).
ADD myNode.

PRINT "Start circularization burn in approx. "+round(eta:apoapsis-burnDuration/2)+" s".

WAIT 0.05.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
