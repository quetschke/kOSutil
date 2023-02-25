// dock.ks - Dock at target
// Copyright © 2023 V. Quetschke
// Version 0.3, 02/24/2023
@LAZYGLOBAL OFF.

// Docking script that uses RCS to dock with a target docking port.
// Requirements:
// 1. Be closer than 200m from target vessel.
// 2. A docking port on the target vessel needs to be set as target.
//    (Use 'Set as Target' on other the vessel when closer than 200m.)
//    If TARGET is set to a docking port, the variable will after a short time
//    switch back to targeting the corresponding vessel if the distances
//    increases to over 200m.
// 3. The docking port on this (the docking) vessel needs to be active with
//    'Control from here'.

// Procedure
// x. The script first sets an intermediate target, some (imDist) meters in front of
//    the target docking port. That position is corrected so that the docking port of
//    the docking vessel, when rotated around the center of mass (CM) on the corrected
//    intermediate target, is aligned on the axis of the facing off the target docking
//    port.
// x. The vector perpendicular to plane created by the vector pointing from the ship to the
//    target docking port and the direction the target docking port faces defines the Top
//    direction of the system (taTop). TaTop is created
//    by the cross product: (Left handed!!)
//    VCRS(myTarget:POSITION:NORMALIZED,myTarget:PORTFACING:VECTOR):NORMALIZED.
// x. The direction the target docking port faces defines Fore (taFore).
// x. taFore and taTop define taStar pointing Starboard (right) from the direction of the
//    target docking port.
// x. If the angle between the target docing port and the vector pointing to the intermediate
//    target is less than 90deg, the target docking port is facing away from the docking vessel.
//    In this case add another intermediate target (imDist) meters pointing to the right
//    (taStar) to the first intermediate target to define an earlier intermediate target.
// Flight plan:
// 1. If a second intermediate target exists, point the vessel there, accelerate forward
//    until the vessel reaches the maximum forward velocity (maxForeSpeed) or the mimimum
//    stopping distance at the current speed is 40% of the distance to the intermediate target.
//    Break until the vessel comes to a complete stop at the intermediate target.
// 2. Repeat the procedure from 1 for the intermediate target (imDist) meters in front of
//    the target docking port.
// 3. Rotate (around CM) until the docking ports face each other.
//    Accelerate until DockSpeed is reached, coast forward and dock.
// During 1, 2 control loops atempt to minimize the deviation from the target velocities and
// during the final approach a control loop minimizes the deviation from the center of the
// target docking port.


// Set global parameters #open
LOCAL maxForeSpeed TO 300.
LOCAL imDist TO 10.
LOCAL DockSpeed TO 0.3.
// Minimum speed deviation that the control loops try to achieve.
LOCAL minSpeed TO 0.003.
// Factor so that RCS fine control values (CoFor, CoBack, ...) change the velocity according to
// minspeed = minSpdF*CoXXX*DelT.
LOCAL minSpdF TO 1/3.
// #close

// Some debug settings #open
LOCAL ShowVectors TO FALSE. // If true draw help arrows.

LOCAL dbg TO FALSE. // Silence some output
LOCAL NiceRot TO TRUE. // Cosmetic use. See below.
// #close

// Performance settings #open
// Tweak PID for faster STEERING angle acquisition. Default Ki is 0.1.
SET STEERINGMANAGER:YAWPID:Ki TO 0.25.
SET STEERINGMANAGER:PITCHPID:Ki TO 0.25.
//SET STEERINGMANAGER:ROLLPID:Ki TO 0.25.
// #close

// Initialization #open
RUNONCEPATH("libcommon"). // Load helper functions.

// Store current IPU value.
LOCAL myIPU TO CONFIG:IPU.
SET CONFIG:IPU TO 2000. // Makes the timing a little better.

CLEARSCREEN.
CLEARVECDRAWS().
// #close

// Derived variables and functions #open
LOCAL mypi TO constant:pi.
LOCAL DelT TO KUNIVERSE:TIMEWARP:PHYSICSDELTAT.
IF KUNIVERSE:TIMEWARP:RATE <> 1 {
    PRINT "Do not WARP when startimg the script!".
    PRINT " ".
    PRINT 1/0.
}

LOCAL loopTime IS TIME:SECONDS. // User for timing the main loops below.

// Directions of the docking vessel
LOCK myup TO -BODY:POSITION:NORMALIZED.
LOCK myprograde TO SHIP:PROGRADE:VECTOR.

// Left handed coordinate system!
LOCK mynorm TO VCRS(BODY:POSITION, SHIP:VELOCITY:ORBIT):NORMALIZED.
LOCK myhoriz TO VCRS(-BODY:POSITION,mynorm):NORMALIZED.

// Left handed coordinate system!
LOCK myrad TO VCRS(mynorm, SHIP:VELOCITY:ORBIT):NORMALIZED.

// Locks to make it shorter.
LOCK myTop TO SHIP:FACING:TOPVECTOR.
LOCK myFore TO SHIP:FACING:VECTOR.
LOCK myStar TO SHIP:FACING:STARVECTOR.

// Stopping distance - at RCS fore thrust
// https://physics.info/motion-equations/ eq [3]
FUNCTION stopDist {
    // Assumes a scalar
    PARAMETER myVel.    // Velocity
    // Assumes we only use Backward acceleration. Assume some inefficiency. Operate at 98%
    RETURN (myVel^2 - 0^2) / (2*RThBack/SHIP:MASS*0.98).
}


FUNCTION waitAlign {
    // Wait for STEERING to settle to within errordiv units
    PARAMETER errordiv.    // Max target deviation

    //LOCAL alignTime IS TIME:SECONDS.
    LOCAL k TO 1/6. // EMA parameter
    LOCAL errorsig TO 1. //ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR).
    UNTIL errorsig < errordiv {
        WAIT 0.01.
        SET errorsig TO errorsig*(1-k) + (ABS(SteeringManager:ANGLEERROR) + ABS(SteeringManager:ROLLERROR)/10)*k.
        PRINT ROUND(errorsig,3)+"   " AT(15,15).
    }
    //PRINT ROUND(TIME:SECONDS-alignTime,1)+"   " AT(30,15).
    RETURN.
}
// #close

// RCS variables #open
// RCS thrust in the respective directions.
LOCAL RThFor TO 0.
LOCAL RThBack TO 0.
LOCAL RThUp TO 0.
LOCAL RThDown TO 0.
LOCAL RThRight TO 0.
LOCAL RThLeft TO 0.

LOCAL RFlowFor TO 0.
LOCAL rcsfuellex TO STAGE:RESOURCESLEX["MonoPropellant"].
LOCK rcsfuel TO rcsfuellex:AMOUNT.
LOCAL rcsdensity TO rcsfuellex:DENSITY.
LOCK massDV TO SHIP:MASS-rcsfuel/2*rcsdensity.  // Ship mass without half RCS fuel for DV calc.
LOCAL massNoRCS TO SHIP:MASS-rcsfuel*rcsdensity. // Ship mass without RCS fuel for CoXXX calc.

LOCAL RCSThruVecOK TO FALSE.
LOCAL RCSvariantLex TO LEXICON(). // See explanation below.
IF CORE:VERSION:MAJOR <> 1 OR CORE:VERSION:MINOR > 3 {
    // kOS 1.4.0 fixed the THRUSTVECTORS list.
    SET RCSThruVecOK TO TRUE.
} ELSE {
    // Problem: kOS 1.3.2 does not use part variants for THRUSTVECTORS correctly,
    // instead all possible thrust vector directions in all variants are listed
    // in RCS:THRUSTVECTORS.
    // As a workaround use kOS tag, or default to first variant if missing.
    SET RCSvariantLex TO LEXICON(
        "RCSblock.01.small", LIST(
            LIST(1,1,1,1,0,0,0,0,0), // The first 4 are in plane, but angled
            LIST(0,0,0,0,1,1,1,1,1), // Left, right, up, down, and out
            LIST(0,0,0,0,1,1,1,1,0), // Left, right, up, down
            LIST(0,0,0,0,0,0,1,1,1), // Up, down, and out
            LIST(0,0,0,0,0,0,1,1,0) // Up, down
        ),  // Small RCS block
        "RCSBlock.v2", LIST(
            LIST(1,1,1,1,0,0,0,0,0), // The first 4 are in plane, but angled
            LIST(0,0,0,0,1,1,1,1,1), // Left, right, up, down, and out
            LIST(0,0,0,0,1,1,1,1,0), // Left, right, up, down
            LIST(0,0,0,0,0,0,1,1,1), // Up, down, and out
            LIST(0,0,0,0,0,0,1,1,0) // Up, down
        )  // Big RCS block
    ).
}

// If we don't have thrust we likely have not staged yet. This is just an initializing problem to make
// STAGE:RESOURCESLEX["MonoPropellant"]:AMOUNT work.
IF rcsfuel = 0 AND MAXTHRUST = 0 {
    PRINT "Staging to initialize RCS fuel.".
    STAGE.
    UNTIL STAGE:READY { WAIT 0. }
    //SET rcsfuel TO STAGE:RESOURCESLEX["MonoPropellant"]:AMOUNT.
    // If it is still 0, we probaly have other issues.
}

LOCAL HasWarning TO FALSE. // Shows warnings for 2s if warnings are found.
LOCAL myRCS TO 0.
LIST RCS IN myRCS.
// Loop over all RCS parts.
FOR thr IN myRCS {
    LOCAL vR TO LIST(0,0,0,0,0,0,0,0,0,0). // Creates a new empty list
    LOCAL i TO 0.

    // Disable RCS for pitch. yaw and roll
    SET thr:PITCHENABLED TO FALSE.
    SET thr:YAWENABLED TO FALSE.
    SET thr:ROLLENABLED TO FALSE.

    LOCAL kTag TO thr:GETMODULE("KOSNameTag"):GETFIELD("name tag").

    IF dbg {
        PRINT "RCS Name: " + thr:NAME.
        PRINT "RCS Title: " + thr:TITLE.
        PRINT "kOS tag: <"+kTag+">".
        PRINT "Vacuum MAXTHRUST = " + thr:MAXTHRUSTAT(0).
        PRINT "The THRUSTVECTORS list has n = " + thr:THRUSTVECTORS:LENGTH + " entries".
    }
    // Indicates which entries of THRUSTVECTORS are active. See RCSvariantLex entry definition
    // for more details.
    LOCAL rcsvariant TO LIST().
    IF RCSThruVecOK { // All thr:THRUSTVECTORS are OK. - kOS 1.4.0
    } ELSE {
        // Brutal workaround! All RCS thrusters with 2 or 1 variants have only one
        // horn/thrustvector. This might fail for modded parts!
        IF thr:THRUSTVECTORS:LENGTH <= 2 {
            // The 'Place Anywhere 1 Linear' RCS Port has two variants, but only one horn.
            // Note: FixMe: Really? Check this!
            SET rcsvariant TO LIST(1,0).
        } ELSE {
            // Check if we know that RCS block.
            IF NOT RCSvariantLex:HASKEY(thr:NAME) {
                PRINT " ".
                PRINT "No variant information for:".
                PRINT "   "+thr:TITLE+" / "+thr:NAME.
                PRINT "Unable to predict thrust directions.".
                PRINT "Add RCS block to RCSvariantLex.".
                PRINT " ".
                PRINT 1/0.
            }
            LOCAL rvar TO 0.
            // RCS variant tags are expected to be "v:num", with num being the variant.
            IF kTag:STARTSWITH("v:") {
                SET rvar TO kTag:REMOVE(0,2):TONUMBER(-1).
                IF rvar < 0 OR rvar <> ROUND(rvar,0) {
                    PRINT "RCS variant number not valid <"+kTag+">".
                    PRINT "Set to 0.".
                    SET rvar TO 0.
                    SET HasWarning TO TRUE.
                }
            } ELSE {
                PRINT thr:TITLE+" - No RCS tag found. Assume <v:0>.".
                SET HasWarning TO TRUE.
            }
            SET rcsvariant TO RCSvariantLex[thr:NAME][rvar].
        }
    }

    // Collect the cumulative thrust in the principal ship directions.
    FOR ivec IN thr:THRUSTVECTORS {
        IF RCSThruVecOK OR rcsvariant[i] > 0 {
            LOCAL tFore TO VDOT(ivec,myFore).
            // Draw vectors to identify thrusters
            // -thr:FACING:STARVECTOR is oriented perpendicular to the mounting surface.
            //SET vR[i] TO VECDRAW( thr:POSITION-thr:FACING:STARVECTOR*0.1, ivec*0.5, red,i).
            //SET vR[i]:show to true.

            IF tFore > 0 {
                SET RThFor TO RThFor + tFore*thr:AVAILABLETHRUSTAT(0).
                // Flow at tweaked limit
                SET RFlowFor TO RFlowFor + tFore*thr:MAXFUELFLOW*thr:AVAILABLETHRUSTAT(0)/thr:MAXTHRUSTAT(0).
            } ELSE {
                SET RThBack TO RThBack - tFore*thr:AVAILABLETHRUSTAT(0).
            }
            LOCAL tTop TO VDOT(ivec,mytop).
            IF tTop > 0 {
                SET RThUp TO RThUp + tTop*thr:AVAILABLETHRUSTAT(0).
            } ELSE {
                SET RThDown TO RThDown - tTop*thr:AVAILABLETHRUSTAT(0).
            }
            LOCAL tStar TO VDOT(ivec,mystar).
            IF tStar > 0 {
                SET RThRight TO RThRight + tStar*thr:AVAILABLETHRUSTAT(0).
            } ELSE {
                SET RThLeft TO RThLeft - tStar*thr:AVAILABLETHRUSTAT(0).
            }
        }
        SET i TO i+1.
    }
}

// RCS control setting, limited to have velocity change less than
// minspeed*minSpdF per physics tick. We use massNoRCS to use the maximum
// possible acceleration in the calculation.
//   a_max = RThXXX/massNoRCS .. max RCS acceleration.
//   a_co = minSpdF*minSpeed/DelT .. Desired acceleration.
// a_co / a_max is the RCS raw control setting to acive the desired acceleration.
LOCAL CoFor TO MIN(minSpdF*minSpeed/DelT/(RThFor/massNoRCS),1).
IF CoFor < 0.05 {
    SET HasWarning TO TRUE.
    PRINT "Too much Forward RCS thrust to satisfy minSpeed. Forward minimum speed delta: "
          +ROUND(DelT*0.05*RThFor/massNoRCS,4). SET CoFor TO 0.05.
}
LOCAL CoBack TO MIN(minSpdF*minSpeed/DelT/(RThBack/massNoRCS),1).
IF CoBack < 0.05 {
    SET HasWarning TO TRUE.
    PRINT "Too much Back RCS thrust to satisfy minSpeed. Backward minimum speed delta: "
          +ROUND(DelT*0.05*RThBack/massNoRCS,4). SET CoBack TO 0.05.
}
LOCAL CoRight TO MIN(minSpdF*minSpeed/DelT/(RThRight/massNoRCS),1).
IF CoRight < 0.05 {
    SET HasWarning TO TRUE.
    PRINT "Too much Right RCS thrust to satisfy minSpeed. Right minimum speed delta: "
          +ROUND(DelT*0.05*RThRight/massNoRCS,4). SET CoRight TO 0.05.
}
LOCAL CoLeft TO MIN(minSpdF*minSpeed/DelT/(RThLeft/massNoRCS),1).
IF CoLeft < 0.05 {
    SET HasWarning TO TRUE.
    PRINT "Too much Left RCS thrust to satisfy minSpeed. Left minimum speed delta: "
          +ROUND(DelT*0.05*RThLeft/massNoRCS,4). SET CoLeft TO 0.05.
}
LOCAL CoUp TO MIN(minSpdF*minSpeed/DelT/(RThUp/massNoRCS),1).
IF CoUp < 0.05 {
    SET HasWarning TO TRUE.
    PRINT "Too much Up RCS thrust to satisfy minSpeed. Up minimum speed delta: "
          +ROUND(DelT*0.05*RThUp/massNoRCS,4). SET CoUp TO 0.05.
}
LOCAL CoDown TO MIN(minSpdF*minSpeed/DelT/(RThDown/massNoRCS),1).
IF CoDown < 0.05 {
    SET HasWarning TO TRUE.
    PRINT "Too much Down RCS thrust to satisfy minSpeed. Down minimum speed delta: "
          +ROUND(DelT*0.05*RThDown/massNoRCS,4). SET CoDown TO 0.05.
}

// Clear warining information.
IF HasWarning {
    PRINT "Erasing warnings in 2s".
    VO:PLAY(vTick).
    WAIT 2.
    VO:PLAY(vTick).
    CLEARSCREEN.
}
//#close RCS parameters

// Vessel statistics output #open
PRINT "Docking helper script".
PRINT "---------------------------------------------".
PRINT "Ship mass:"+nuform(SHIP:MASS,3,1)+" t;  RCS fuel: "+nuform(rcsfuel,3,1)+" u / "
                  +ROUND(rcsfuel*rcsdensity,1)+" t".
PRINT " ".
PRINT "Forw. max DV:"+nuform(RThFor/massDV*rcsfuel/RFlowFor,4,1)+" m/s; dur.:"
                     +nuform(rcsfuel/RFlowFor,4,1)+" s; Accel.:"
                     +nuform(RThFor/SHIP:MASS,2,2)+" m/s2".
PRINT "                         MinSpd target: "+nuform(minSpeed,1,4).
PRINT "Fore/Back:"+nuform(RThFor,3,2)+"/"+nuform(RThBack,3,2)+" kN   "
        +"MinSpd: "+nuform(DelT*CoFor*RThFor/massNoRCS,1,4)+"/"+nuform(DelT*CoBack*RThBack/massNoRCS,1,4)
        +" Co:"+nuform(CoFor,1,3)+"/"+nuform(CoBack,1,3).
PRINT "Rght/Left:"+nuform(RThRight,3,2)+"/"+nuform(RThLeft,3,2)+" kN   "
        +"MinSpd: "+nuform(DelT*CoRight*RThRight/massNoRCS,1,4)+"/"+nuform(DelT*CoLeft*RThLeft/massNoRCS,1,4)
        +" Co:"+nuform(CoRight,1,3)+"/"+nuform(CoLeft,1,3).
PRINT "Up/Down:  "+nuform(RThUp,3,2)+"/"+nuform(RThDown,3,2)+" kN   "
        +"MinSpd: "+nuform(DelT*CoUp*RThUp/massNoRCS,1,4)+"/"+nuform(DelT*CoDown*RThDown/massNoRCS,1,4)
        +" Co:"+nuform(CoUp,1,3)+"/"+nuform(CoDown,1,3).
PRINT " ".
PRINT "10 ".
PRINT " ".
PRINT " ".
PRINT "Stopdist:          Reldist:            Delta:".
PRINT "WhenTime:          LoopTime".
PRINT "Alignment:". // line 15
PRINT "----------------------------------------------".
// #close

// Target vessel and docking port variables and preparation #open
// Docking port info for current vessel
LOCAL actport TO SHIP:CONTROLPART.
IF NOT actport:ISTYPE("DockingPort") {
    PRINT "Docking port needs to be active with ``Control from here''!".
    PRINT "Abort!".
    PRINT " ".
    PRINT 1/0.
}

// Find direction to target
IF NOT HASTARGET OR TARGET:TYPENAME <> "DockingPort"{
    PRINT "Target needs to be set to a docking port on the target vessel!".
    PRINT "Select 'Set as Target' on other vessel when closer than 200m.".
    PRINT " ".
    PRINT 1/0.
}
LOCAL myTarget TO TARGET.

// Rotation around CM. For the target vessel we need to use the docking port forevector,
// the topvector so that it is perpendicular to the plane of
//  myTarget:POSITION X actport:PORTFACING:VECTOR
// and the starvector that is perpendicular on those two.
LOCK taFore TO myTarget:PORTFACING:VECTOR.
// Attention! Normalize cross products
LOCK taTop TO VCRS(myTarget:POSITION:NORMALIZED,myTarget:PORTFACING:VECTOR):NORMALIZED.
LOCK taStar TO VCRS(taTop, myTarget:PORTFACING:VECTOR):NORMALIZED.

// Vector from CM to docking port
LOCK CMoffset TO actport:POSITION.

// intermediate target, some meters in front of docking port.
LOCK imTargetPos1 TO myTarget:POSITION+myTarget:PORTFACING:VECTOR*imDist.

// Add the offset of the docking port from the CM of the docking vessel to the location of the
// docing port of the target vessel in the coordinates of the target vessel. When being at this
// position and rotated around CM the docking ports of both vessels will match.
LOCK taCMcorr TO taFore*VDOT(CMoffset,myFore) + taTop*VDOT(CMoffset,myTop) + taStar*VDOT(CMoffset,myStar).
// intermediate target, some meters in front of docking port and CM corrected. (ImTarPosCM1)
LOCK ImTarPosCM1 TO imTargetPos1+taCMcorr.

LOCK relVel TO myTarget:SHIP:VELOCITY:ORBIT-SHIP:VELOCITY:ORBIT. // Opposite to pilots perspective

// Set vector from docking port to target docking port, instead of from CM.
LOCK dockRelDist TO myTarget:POSITION-actport:POSITION.
// #close

// For ImTarPosCM1
LOCK relDist TO ImTarPosCM1-SHIP:POSITION. // SHIP:POSITION is 0
LOCAL curTarget TO "intermediate position 1".

PRINT "Angle between intermed. target and docking port dir.: "
    +ROUND(VANG(ImTarPosCM1,myTarget:PORTFACING:VECTOR),1).
LOCAL ImTarPosCM2 TO V(0,0,0).
LOCAL iTarNum TO 1.

// Rotate the vector from Target to ImTarPosCM1 by 85deg in the plane of the two vessels, toward the docking
// vessel if the docking port is pointing away.
IF VANG(ImTarPosCM1,myTarget:PORTFACING:VECTOR) < 85 { // Docking port pointing away.
    // Set Intermediate position 2 information.
    PRINT "Setting additional intermediate target!".
    // LOCK is GLOBAL
    LOCK ImTarPosCM2 TO ImTarPosCM1+taStar*imDist.
    LOCK relDist TO ImTarPosCM2-SHIP:POSITION. // SHIP:POSITION is 0
    SET curTarget TO "intermediate position 2".
    SET iTarNum TO 2. // Two intermediate positions.
}
PRINT "Angle between target dir and docking port dir.: "
      +ROUND(VANG(relDist,SHIP:FACING:FOREVECTOR),1).

// Draw vectors for debugging
IF ShowVectors {
    // In mapview extend arrows
    LOCAL vextend TO 1.
    LOCAL runVec TO True.
    WHEN defined runVec THEN {
        IF MAPVIEW {
            SET vextend TO 500.
        } ELSE {
            SET vextend TO 1.
        }
        RETURN runVec.  // Removes the trigger when runVec is false
    }

    IF ImTarPosCM2 <> V(0,0,0) {
        // Other vessel arrow to imTarPosCM2
        LOCAL vTPort3 TO VECDRAW( { return ImTarPosCM1.},
                                { return ImTarPosCM2-ImTarPosCM1. },
                                blue,"ImTarPosCM2").
        SET vTPort3:show to true.

        LOCAL vTarget2 TO VECDRAW( { return V(0,0,0).},
                                { return ImTarPosCM2. },
                                green,"target 2").
        SET vTarget2:show to true.
    }

    LOCAL vtop TO VECDRAW(V(0,0,0), { return 5*myTop*vextend. }, white,"TOP").
    SET vtop:show to true.

    LOCAL vfore TO VECDRAW(V(0,0,0), { return 5*myFore*vextend. }, white,"FORE").
    SET vfore:show to true.

    LOCAL vstar TO VECDRAW(V(0,0,0), { return 5*myStar*vextend. }, white,"STAR").
    SET vstar:show to true.

    LOCAL vCM TO VECDRAW( { return myTop*0.},
                            { return CMoffset. },
                            green,"CM offset").
    SET vCM:show to true.

    // CM corrected target
    LOCAL vCMt TO VECDRAW( { return imTargetPos1.},
                            { return taCMcorr. },
                            red,"CMt").
    SET vCMt:show to true.

    // Our port, 1m sticking out.
    LOCAL vPort TO VECDRAW( { return actport:POSITION+actport:PORTFACING:VECTOR*0.3.},
                            { return actport:PORTFACING:VECTOR. },
                            yellow,"dock").
    SET vPort:show to true.

    // Target port, 1m vector sticking out.
    LOCAL vTPort TO VECDRAW( { return myTarget:POSITION+myTarget:PORTFACING:VECTOR*0.3.},
                            { return myTarget:PORTFACING:VECTOR. },
                            green,"dock target").
    SET vTPort:show to true.

    LOCAL vTarget1 TO VECDRAW( { return V(0,0,0).},
                            { return imTargetPos1+taCMcorr. },
                            green,"target 1").
    SET vTarget1:show to true.

    // Other vessel arrow to imTargetPos1
    LOCAL vTPort2 TO VECDRAW( { return myTarget:POSITION+myTarget:PORTFACING:VECTOR*1.5.},
                            { return imTargetPos1-myTarget:POSITION-myTarget:PORTFACING:VECTOR*1.5. },
                            blue,"imTargetPos1").
    SET vTPort2:show to true.

    // Test
    LOCAL vTaDir TO VECDRAW( { return imTargetPos1.},
                            { return taTop*5. },
                            white,"taTop").
    SET vTaDir:show to true.
}

//display info
LOCAL whenTime IS TIME:SECONDS.
LOCAL runDOCK TO true.
WHEN defined runDOCK THEN {
    PRINT "RCS left (u): "+ROUND(rcsfuel,1)+"  " AT(20,3).
    PRINT "DV: "+ROUND(RThFor/massDV*rcsfuel/RFlowFor,1)+"  " AT(10,5).
    PRINT "Target: "+curTarget AT(0,10).
    PRINT "Dist. F: "+ROUND(relDist*myFore,2)
        +" T:"+ROUND(relDist*myTop,2)+" R:"+ROUND(relDist*myStar,2)+"    " AT(0,11).
    PRINT "Rel.v. F:"+ROUND(relVel*myFore,3)
        +" T:"+ROUND(relVel*myTop,3)+" R:"+ROUND(relVel*myStar,3)+"    " AT(0,12).

    PRINT ROUND((TIME:SECONDS-whenTime)*1000,1)+"   " AT (10,14).
    SET whenTime TO TIME:SECONDS.
    RETURN runDOCK.  // Removes the trigger when runDOCK is false
}

// Start the docking ...
RCS ON.
SAS OFF.

// Align vessel so that top is perpendicular to the plane of the
//  vector pointing to myTarget X myTarget:PORTFACING:VECTOR
LOCK STEERING TO LOOKDIRUP(relDist,taTop).
// Wait for alignment
PRINT "Waiting for "+ROUND(VANG(SHIP:FACING:FOREVECTOR,STEERING:VECTOR),1)+"deg alignment ...".
WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR,STEERING:VECTOR) <  0.5.

// Intermediate approach(es).
LOCAL keepTop TO FALSE.
LOCAL iLoop TO iTarnum.
UNTIL iLoop < 1 {
    // Needs: relDist, curTarget
    IF iLoop < iTarNum {
        // 2nd loop. For ImTarPosCM1
        LOCK relDist TO ImTarPosCM1-SHIP:POSITION. // SHIP:POSITION is 0
        LOCAL curTarget TO "intermediate position 1".
        // 2nd loop. Up to 90 deg turn is needed.
        PRINT "Waiting for "+ROUND(VANG(SHIP:FACING:FOREVECTOR,relDist),1)+"deg alignment ...".
        // The NiceRot section is not strictly needed, but setting the STEERING direction leads to
        // a "tumble" instead of a pure Yaw rotation. Giving the vessel a nudge first makes the
        // movement look better.
        IF NiceRot {
            UNLOCK STEERING.
            LOCAL StartAngle TO VANG(relDist, myFore).
            SET SHIP:CONTROL:YAW TO -1.
            WAIT UNTIL VANG(relDist, myFore) < StartAngle*85/90.
            SET SHIP:CONTROL:YAW TO 0.
        }
        LOCK STEERING TO LOOKDIRUP(relDist,taTop).
        // Wait for alignment
        waitAlign(0.5).
    }

    // Calculate maximum forward velocity so that 40% of the total distance are needed to stop
    // at maximum deceleration
    LOCAL imForeSpeed TO MIN(maxForeSpeed,SQRT(2*RThBack/SHIP:MASS*0.4*relDist:MAG)).
    PRINT "Maximum forward speed: "+ROUND(imForeSpeed,3).

    // Wait until the needed stopping distance to reach 0m/s is just larger than
    // the current distance.
    PRINT "Waiting to reach stopping distance ...".
    SET loopTime TO TIME:SECONDS.
    UNTIL stopDist(relVel*myFore) >= relDist*myFore*0.95 { // Safety margin 5%
        PRINT ROUND((TIME:SECONDS-loopTime)*1000,1)+"  " AT (30,14).
        SET loopTime TO TIME:SECONDS.
        LOCAL DT_Mass TO DelT/SHIP:MASS.
        IF -relVel*myFore < imForeSpeed {
            SET SHIP:CONTROL:FORE TO 1.
        } ELSE IF -relVel*myFore > imForeSpeed*1.02 {
            SET SHIP:CONTROL:FORE TO -1.
        } ELSE {
            SET SHIP:CONTROL:FORE TO 0.
        }
        // Up/down
        LOCAL relTopVel TO relVel*myTop.
        IF ABS(relTopVel) > 10*minSpeed { //Save fuel by only aiming for 10*minSpeed
            // Use "fine" RCS control if velocity change per physics tick is greater than the difference
            // between current velocity and minimum targeted velocity.
            IF relTopVel > 0 { // Going down. Sign is weird
                LOCAL SCTop TO CHOOSE 1 IF ABS(relTopVel)-10*minSpeed>RThUp*DT_Mass ELSE CoUp.
                SET SHIP:CONTROL:TOP TO SCTop. // Accelerate up
            } ELSE {
                LOCAL SCTop TO CHOOSE 1 IF ABS(relTopVel)-10*minSpeed>RThDown*DT_Mass ELSE CoDown.
                SET SHIP:CONTROL:TOP TO -SCTop.
            }
        } ELSE {
            SET SHIP:CONTROL:TOP TO 0.
        }
        // Right/Left
        LOCAL relStarVel TO relVel*myStar.
        IF ABS(relStarVel) > 10*minSpeed {
            LOCAL SCStar TO CHOOSE 1 IF ABS(relVel*myStar)-10*minSpeed>RThRight*DT_Mass ELSE CoRight.
            IF relStarVel > 0 { // Going left.
                LOCAL SCStar TO CHOOSE 1 IF ABS(relStarVel)-10*minSpeed>RThRight*DT_Mass ELSE CoRight.
                SET SHIP:CONTROL:STARBOARD TO SCStar.
            } ELSE {
                LOCAL SCStar TO CHOOSE 1 IF ABS(relStarVel)-10*minSpeed>RThLeft*DT_Mass ELSE CoLeft.
                SET SHIP:CONTROL:STARBOARD TO -SCStar.
            }
        } ELSE {
            SET SHIP:CONTROL:STARBOARD TO 0.
        }
        WAIT 0.
    }

    // Suicide breaking to stop at intermediate target position.
    LOCAL SLocked TO FALSE.

    PRINT "Breaking ...".
    SET SHIP:CONTROL:FORE TO -1.
    SET loopTime TO TIME:SECONDS.
    UNTIL -relVel*myFore < minSpeed {
        PRINT ROUND((TIME:SECONDS-loopTime)*1000,1)+"  " AT (30,14).
        SET loopTime TO TIME:SECONDS.

        LOCAL DT_Mass TO DelT/SHIP:MASS.
        LOCAL relForeVel TO relVel*myFore.
        LOCAL myStopDist TO stopDist(relForeVel).
        LOCAL myRelDist TO relDist*myFore.
        PRINT ROUND(myStopDist,2)+"   " at (10,13).
        PRINT ROUND(myRelDist,2)+"   " at (30,13).
        PRINT ROUND(myRelDist-myStopDist,2)+"   " AT(50,13).

        // Slow down
        IF myStopDist > myRelDist*0.98 { // 2% safety margin. 2cm on one meter.
            LOCAL SCFore TO CHOOSE 1 IF ABS(relForeVel)-minSpeed>RThBack*DT_Mass ELSE CoBack.
            SET SHIP:CONTROL:FORE TO -SCFore.
        } ELSE IF myStopDist < myRelDist*0.90 { // 10% margin
            SET SHIP:CONTROL:FORE TO 0.
        }

        // Up/down
        LOCAL relTopVel TO relVel*myTop.
        IF ABS(relTopVel) > minSpeed {
            // Use "fine" RCS control if velocity change per physics tick is greater than the difference
            // between current velocity and minimum targeted velocity.
            IF relTopVel > 0 { // Going down. Sign is weird
                LOCAL SCTop TO CHOOSE 1 IF ABS(relTopVel)-minSpeed>RThUp*DT_Mass ELSE CoUp.
                SET SHIP:CONTROL:TOP TO SCTop. // Accelerate up
            } ELSE {
                LOCAL SCTop TO CHOOSE 1 IF ABS(relTopVel)-minSpeed>RThDown*DT_Mass ELSE CoDown.
                SET SHIP:CONTROL:TOP TO -SCTop.
            }
        } ELSE {
            SET SHIP:CONTROL:TOP TO 0.
        }
        // Right/Left
        LOCAL relStarVel TO relVel*myStar.
        IF ABS(relStarVel) > minSpeed {
            LOCAL SCStar TO CHOOSE 1 IF ABS(relVel*myStar)-minSpeed>RThRight*DT_Mass ELSE CoRight.
            IF relStarVel > 0 { // Going left.
                LOCAL SCStar TO CHOOSE 1 IF ABS(relStarVel)-minSpeed>RThRight*DT_Mass ELSE CoRight.
                SET SHIP:CONTROL:STARBOARD TO SCStar.
            } ELSE {
                LOCAL SCStar TO CHOOSE 1 IF ABS(relStarVel)-minSpeed>RThLeft*DT_Mass ELSE CoLeft.
                SET SHIP:CONTROL:STARBOARD TO -SCStar.
            }
        } ELSE {
            SET SHIP:CONTROL:STARBOARD TO 0.
        }

        // Lock in the steering direction
        IF NOT SLocked AND myRelDist < 2 { //:NORMALIZED
            // Use current dp facing and target dp facing.
            SET keepTop TO VCRS(actport:PORTFACING:VECTOR, myTarget:PORTFACING:VECTOR):NORMALIZED.
            LOCK taTop TO keepTop. // Make the value a constant.

            // Lock in the steering direction
            LOCAL keepSTEER TO LOOKDIRUP(actport:PORTFACING:VECTOR,taTop).
            LOCK STEERING TO keepSTEER.

            PRINT "Locked STEERING at distance "+ROUND(myRelDist,1)+" m".
            SET SLocked TO TRUE.
        }
        WAIT 0.
    }
    SET SHIP:CONTROL:FORE TO 0.
    SET SHIP:CONTROL:STARBOARD TO 0.
    SET SHIP:CONTROL:TOP TO 0.
    PRINT "Stopped at intermediate pos "+iLoop+".".
    PRINT "Dist. abs: "+nuform(relDist:MAG,3,2)+" F:"+nuform(relDist*myFore,4,2)
            +" T:"+nuform(relDist*myTop,3,2)+" R:"+nuform(relDist*myStar,3,2).
    PRINT "Rel.v. abs:"+nuform(relVel:MAG,3,2)+" F:"+nuform(relVel*myFore,4,2)
            +" T:"+nuform(relVel*myTop,3,2)+" R:"+nuform(relVel*myStar,3,2).
    PRINT "Angle "+ROUND(VANG(actport:PORTFACING:VECTOR,myTarget:PORTFACING:VECTOR),1)+"deg.".

    SET iLoop TO iLoop-1.
}

// Switch to final target
LOCAL curTarget TO "Docking port".
LOCK relDist TO dockRelDist. // This includes the docking port postition!

// We are at 90deg angle
LOCAL keepTop TO VCRS(actport:PORTFACING:VECTOR,myTarget:PORTFACING:VECTOR):NORMALIZED.
LOCK taTop TO keepTop. // Make the value a constant.

// Turn to face docking port.
PRINT "Waiting for "+ROUND(VANG(SHIP:FACING:FOREVECTOR,-myTarget:PORTFACING:VECTOR),1)+"deg alignment ...".
// This sections is not strictly needed, but setting the STEERING direction (see next LOCK STEERING)
// leads to a "tumble" instead of a pure Yaw rotation. Giving the vessel a nudge first makes the
// movement look better.
IF NiceRot {
    UNLOCK STEERING.
    LOCAL StartAngle TO VANG(-myTarget:PORTFACING:VECTOR, myFore).
    SET SHIP:CONTROL:YAW TO -1.
    WAIT UNTIL VANG(-myTarget:PORTFACING:VECTOR, myFore) < StartAngle*85/90.
    SET SHIP:CONTROL:YAW TO 0.
}
LOCK STEERING TO LOOKDIRUP(-myTarget:PORTFACING:VECTOR,taTop).
waitAlign(0.3).

// In taXXX coordinate system go forward with and minimize the Top and Star
// deviation (of dockRelDist) from the target.
PRINT "Last phase - docking ...".
SET loopTime TO TIME:SECONDS.
UNTIL myTarget:STATE <> "Ready" OR dockRelDist:MAG < 0.6 { // Docking port state
    PRINT ROUND((TIME:SECONDS-loopTime)*1000,1)+"  " AT (30,14).
    SET loopTime TO TIME:SECONDS.

    LOCAL DT_Mass TO DelT/SHIP:MASS.

    // Accelerate/decelerate
    IF -relVel*myFore < DockSpeed-minSpeed {
        LOCAL SCFore TO CHOOSE 1 IF ABS(-relVel*myFore -DockSpeed)-minSpeed > RThFor*DT_Mass ELSE CoFor.
        SET SHIP:CONTROL:FORE TO CoFor.
    } ELSE IF -relVel*myFore > DockSpeed*1.02+minSpeed {
        LOCAL SCFore TO CHOOSE 1 IF ABS(-relVel*myFore -DockSpeed*1.02)-minSpeed > RThBack*DT_Mass ELSE CoBack.
        SET SHIP:CONTROL:FORE TO -CoBack.
    } ELSE {
        SET SHIP:CONTROL:FORE TO 0.
    }

    // Up/down
    LOCAL cVelTop TO -dockRelDist*myTop.  // Set control vel to deviation / s.
    LOCAL relTopVel TO relVel*myTop.
    IF ABS(relTopVel-cVelTop) > minSpeed {
        // Use "fine" RCS control if velocity change per physics tick is greater than the difference
        // between current velocity and minimum targeted velocity.
        IF relTopVel-cVelTop > 0 { // Going down.
            LOCAL SCTop TO CHOOSE 1 IF ABS(relTopVel-cVelTop)-minSpeed>RThUp*DT_Mass ELSE CoUp.
            SET SHIP:CONTROL:TOP TO SCTop. // Accelerate up
        } ELSE {
            LOCAL SCTop TO CHOOSE 1 IF ABS(relTopVel-cVelTop)-minSpeed>RThDown*DT_Mass ELSE CoDown.
            SET SHIP:CONTROL:TOP TO -SCTop.
        }
    } ELSE {
        SET SHIP:CONTROL:TOP TO 0.
    }

    // Right/Left
    LOCAL cVelStar TO -dockRelDist*myStar.  // Set control vel to deviation / s.
    LOCAL relStarVel TO relVel*myStar.
    IF ABS(relStarVel-cVelStar) > minSpeed {
        // Use "fine" RCS control if velocity change per physics tick is greater than the difference
        // between current velocity and minimum targeted velocity.
        IF relStarVel-cVelStar > 0 { // Going left.
            LOCAL SCStar TO CHOOSE 1 IF ABS(relStarVel-cVelStar)-minSpeed>RThRight*DT_Mass ELSE CoRight.
            SET SHIP:CONTROL:STARBOARD TO SCStar. // Accelerate right
        } ELSE {
            LOCAL SCStar TO CHOOSE 1 IF ABS(relStarVel-cVelStar)-minSpeed>RThDown*DT_Mass ELSE CoLeft.
            SET SHIP:CONTROL:STARBOARD TO -SCStar.
        }
    } ELSE {
        SET SHIP:CONTROL:STARBOARD TO 0.
    }
    WAIT 0.
}
PRINT "Docked at "+ROUND(dockRelDist:MAG,2)+" m. Docking port state: "+myTarget:STATE.
SET SHIP:CONTROL:FORE TO 0.
SET SHIP:CONTROL:STARBOARD TO 0.
SET SHIP:CONTROL:TOP TO 0.
SET runDOCK TO FALSE.
UNLOCK STEERING.
RCS OFF.
SAS ON.

// We only need to wait when we show arrows
IF ShowVectors {
    PRINT " ".
    PRINT "Waiting for user interrupt. Press <DEL> to abort ..".
    UNTIL FALSE {
        WAIT 0.1.
        IF TERMINAL:INPUT:HASCHAR {
            IF TERMINAL:INPUT:GETCHAR() = TERMINAL:INPUT:DELETERIGHT {
                PRINT "Aborted ..".
                BREAK.
            }
        }
    }
    SET runVec TO FALSE.
    CLEARVECDRAWS().
}

SET CONFIG:IPU TO myIPU. // Restores original value.