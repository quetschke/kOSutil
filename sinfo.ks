// sinfo.ks - Get stage info script
// Copyright © 2021 V. Quetschke
// Version 0.3, 05/11/2021
@LAZYGLOBAL OFF.

// Enabling dbg will create a logfile (0:estagedat.log) that can be used for
// improving and debugging the script.
LOCAL dbg TO TRUE.
//LOCAL dbg TO FALSE.

//CLEARSCREEN.
IF dbg { DELETEPATH("0:estagedat.log"). } // Remove old logfile

// Collect stage stats
// Calling stinfo() returns a list of lexicons with the following information:
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

// General structure
// The script is relying on:
// x Stages are counted from the current stage (STAGE:NUMBER) to 0. A value -1 is possible and means never decoupled or never activated.
// x part:DECOUPLEDIN The part is considered part of the vessel until this value is reached. We use
//   lst = part:DECOUPLEDIN-1 (last stage) to track the time when it is still counted for the mass.
// x part:STAGE The part gets staged/activated. ast = part:STAGE.
// The scrip tries to get a stage listing like KER/MJ, with:
// "start mass, end mass, burned mass, staged/dropped mass, thrust, TWR s/e, DV, time"
//
// Stage variables (XX for LiquidFuel, Oxidizer, SolidFuel, XenonGas:
//   XXconst[] fuel flow/consumption in stage where engine is activated
//   XXcon2st[] fuel flow/consumption for later stages until engine is decoupled
//   XXmast[] mass for LiquidFuel, Oxidizer, SolidFuel (todo Xenon)
//   XXthrust[] thrust in stage where engine is activated until stage where engine is decoupled
//   stmass[]
//   
// This is done in several passes:
// 1. First the script loops over all engines to set the consumption per stage and XXconst[] is set for the stage
// the engime is activated. If the engine stays active additional stages record the flow in XXcon2st[].
// Thrust is recorded in XXthrust[]
//
// 2. Then loop over parts ... TBD
//
// Fuel ducts might work automatically if the "inner" fuel gets ast set to the staging value.
// Maybe tweaking is needed.
//
// 3. loop over consumption and fuel info and assign fuel to stage it is burned in.
//
// 4. Finally calculate mass, ISP, dV, thrust, TWR, burntime
// 
// TODO: Include fuel ducts, rework fuel use per stage.

FUNCTION stinfo {
    // Initialize a list of zeroes.
    LOCAL stZ TO LIST().
    FROM {LOCAL I IS 0.} UNTIL i > STAGE:NUMBER STEP {SET I TO I+1.} DO {
      stZ:ADD(0).
    }

    LOCAL lfconst TO stZ:COPY. LOCAL oxconst TO stZ:COPY. LOCAL soconst TO stZ:COPY. LOCAL xeconst TO stZ:COPY.
    LOCAL lfcon2st TO stZ:COPY. LOCAL oxcon2st TO stZ:COPY. LOCAL socon2st TO stZ:COPY. LOCAL xecon2st TO stZ:COPY.
    LOCAL lfmast TO stZ:COPY. LOCAL oxmast TO stZ:COPY. LOCAL somast TO stZ:COPY. LOCAL xemast TO stZ:COPY.
    LOCAL lfthrust TO stZ:COPY. LOCAL oxthrust TO stZ:COPY. LOCAL sothrust TO stZ:COPY. LOCAL xethrust TO stZ:COPY.
    LOCAL stmass TO stZ:COPY. LOCAL burnst TO stZ:COPY.
    LOCAL lfleftst TO stZ:COPY. LOCAL oxleftst TO stZ:COPY. LOCAL xeleftst TO stZ:COPY.

    LOCAL sinfolist TO stZ. // List to store the stage info

    // 9lf to 11ox is the Kerbal rocket fuel relationship. Set that as a const.
    LOCAL ox2lf TO 9.0/11.0.

    IF dbg {
        LOG "Current stage: " + STAGE:NUMBER TO "0:estagedat.log".
        // First loop over engines to set fuelflow/thrust per stage
        LOG "lst,ast,TITLE,MASS,POSSIBLETHRUST,THRUSTLIMIT" TO "0:estagedat.log".
    }
    LOCAL elist TO -999.
    LIST ENGINES IN elist.
    FOR e IN elist {
        // The engine can be active from [ast,lst]
        LOCAL lst is e:DECOUPLEDIN+1.  // Last stage where mass is counted
        LOCAL ast is e:STAGE.  // Stage where part is activated
        LOCAL pthrust IS e:POSSIBLETHRUST.
        LOCAL tlimit IS e:THRUSTLIMIT/100.
        
        IF dbg { LOG lst+","+ast+","+e:TITLE+","+e:MASS+","+pthrust+","+tlimit TO "0:estagedat.log". }
        //LOG "fuelflow: "+e:MAXFUELFLOW TO "0:estagedat.log".

        LOCAL lfcon IS 0. LOCAL oxcon IS 0.
        LOCAL socon IS 0. LOCAL xecon IS 0.
        LOCAL lfthru IS 0. // LF engines have lf and ox flow and thrust.
        LOCAL oxthru IS 0. // NERVs have only lf
        LOCAL sothru IS 0. LOCAL xethru IS 0.
        FOR ftype IN e:CONSUMEDRESOURCES:KEYS {
            LOCAL crtype IS e:CONSUMEDRESOURCES[ftype].
            //LOG crtype:NAME+" flow: "+crtype:MAXFUELFLOW TO "0:estagedat.log".
            IF crtype:NAME = "LiquidFuel" {
                SET lfcon to crtype:MAXFUELFLOW*crtype:DENSITY*tlimit.
            } ELSE IF crtype:NAME = "Oxidizer" {
                SET oxcon to crtype:MAXFUELFLOW*crtype:DENSITY*tlimit.
           } ELSE IF crtype:NAME = "SolidFuel" {
                SET socon to crtype:MAXFUELFLOW*crtype:DENSITY*tlimit.
                SET sothru to pthrust.
            } ELSE IF crtype:NAME = "XenonGas" {
                SET xecon to crtype:MAXFUELFLOW*crtype:DENSITY*tlimit.
                SET xethru to pthrust.
            }
        }
        // Some trickery. Rocket engines use 9u LF per 11u OX. NERV engines use only LF. Both have a density of 0.005t/u.
        // Store rocket engines only under OX and NERV under LF.
        IF lfcon*oxcon > 0 {
            // Rocket engine
            SET oxthru to pthrust.
            SET lfcon to 0. // LF is implied
        } ELSE IF lfcon > 0 {
            // NERV engine
            SET lfthru to pthrust.
        }
        // See comments about XXconst[] and XXcon2st[] above
        SET lfconst[ast] TO lfconst[ast] + lfcon.
        SET oxconst[ast] TO oxconst[ast] + oxcon.
        SET soconst[ast] TO soconst[ast] + socon.
        SET xeconst[ast] TO xeconst[ast] + xecon.
        // Loop from ast to lst
        FROM {local s is ast.} UNTIL s < lst STEP {set s to s-1.} DO {
            SET lfthrust[s] TO lfthrust[s] + lfthru.
            SET oxthrust[s] TO oxthrust[s] + oxthru.
            SET sothrust[s] TO sothrust[s] + sothru.
            SET xethrust[s] TO xethrust[s] + xethru.
            SET lfcon2st[s] TO lfcon2st[s] + lfcon.
            SET oxcon2st[s] TO oxcon2st[s] + oxcon.
            SET socon2st[s] TO socon2st[s] + socon.
            SET xecon2st[s] TO xecon2st[s] + xecon.
        }
    }

    IF dbg {
        LOG "" TO "0:estagedat.log".
        LOG "Fuel consumption per stage" TO "0:estagedat.log".
        LOG "S,LF thru,con,con2,   OX thru,con,con2,   SO thru,con,con2,   XE thru,con,con2" TO "0:estagedat.log".
        FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
            LOG s+","
                +nuform(lfthrust[s],3,1)+","+nuform(lfconst[s],1,4)+","+nuform(lfcon2st[s],1,4)+","
                +nuform(oxthrust[s],3,1)+","+nuform(oxconst[s],1,4)+","+nuform(oxcon2st[s],1,4)+","
                +nuform(sothrust[s],3,1)+","+nuform(soconst[s],1,4)+","+nuform(socon2st[s],1,4)+","
                +nuform(xethrust[s],3,1)+","+nuform(xeconst[s],1,4)+","+nuform(xecon2st[s],1,4) TO "0:estagedat.log".
        }
    }

    // Loop over parts
    LOCAL plist TO -999. LIST PARTS IN plist.
    IF dbg {
        LOG "kst,p:DECOUPLEDIN,p:STAGE,p:TITLE,p:TYPENAME,p:MASS,p:DRYMASS,fuel" TO "0:estagedat.log".
        LOG "" TO "0:estagedat.log".
    }    
    FOR p IN plist {
        LOCAL lst is p:DECOUPLEDIN+1.  // Last stage where mass is counted
        LOCAL ast is p:STAGE.  // Stage where part is activated
        LOCAL kst is lst.  // Stage number like in KER

        LOCAL pmass IS p:DRYMASS. // Fairings change mass. Need this as variable

        IF p:TYPENAME = "Decoupler" {
            // Decouplers have only mass prior to being activated, they stay on without mass
            SET kst TO ast+1.
        } ELSE IF p:TYPENAME = "Engine"{
            // Last time engine mass is counted.
        } ELSE {
            // All other parts. Last time part mass is counted.
        }
        // Log the part
        IF dbg {
            LOG kst+","+p:DECOUPLEDIN+","+p:STAGE+","+p:TITLE+","+p:TYPENAME+","
                +p:MASS+","+p:DRYMASS+","+(p:MASS-p:DRYMASS) TO "0:estagedat.log".
        }

        IF p:TYPENAME = "LaunchClamp" { SET pmass TO 0. } // Ignore mass of clamps.
        
        IF p:TITLE:STARTSWITH("AE-FF") { // A fairing
            LOCAL fpanel IS 0.
            IF p:TITLE:STARTSWITH("AE-FF1 ") { //Note the " " at the end
                SET fpanel TO p:MASS - 0.075.
            } ELSE IF p:TITLE:STARTSWITH("AE-FF1.5") {
                SET fpanel TO p:MASS - 0.15.
            } ELSE IF p:TITLE:STARTSWITH("AE-FF2") {
                SET fpanel TO p:MASS - 0.175.
            } ELSE IF p:TITLE:STARTSWITH("AE-FF3") {
                SET fpanel TO p:MASS - 0.475.
            } ELSE IF p:TITLE:STARTSWITH("AE-FF5") {
                SET fpanel TO p:MASS - 0.8.
            } ELSE {
                PRINT "Unknown fairing!".
                PRINT 10/0.
            }
            // When staged the panel mass is dropped, but on the stage before it is there.
            // Make sure the fairing is not in the active stage
            IF ast < STAGE:NUMBER {
                SET stmass[ast+1] TO stmass[ast+1] + fpanel.
                SET pmass TO pmass - fpanel.
                // When not staged panel and base mass automatically get added to the same stage. (ast+1 = lst)
            }
        }

        // We ignore crossfeed and (maybe) asparagus staging. If a part holds fuel it is only
        // stored in the earliest stage that consumes it and earlier. If a staging occurs because one
        // engine is out of fuel (for example SRB and LF activated, but SRBs separated on next) but
        // others are still running it is safe to assume that the remaining fuel can be moved to the
        // next stage. 
        // Special treatment for fuel tanks/boosters.
        IF p:MASS > p:DRYMASS {
            //LOG "Found a tank or booster!" TO "0:estagedat.log".
            FOR r IN p:RESOURCES {
                // TODO: Rework this. Follow parent and childern. If a decoupler to a lower stage number
                // TODO: exists, use that to determine ast.
                IF r:NAME = "LiquidFuel" {
                   LOCAL s IS lst.
                   UNTIL lfconst[s]+oxconst[s] > 0 or s = STAGE:NUMBER { // Nerv or rocket
                       SET s TO s +1.
                   }
                   IF lfconst[s]+oxconst[s] = 0 {
                       LOG "No consumer found for "+r:NAME TO "0:estagedat.log".
                   }
                   SET lfmast[s] to lfmast[s] + r:DENSITY*r:AMOUNT.
                } ELSE IF r:NAME = "Oxidizer" {
                   LOCAL s IS lst.
                   UNTIL oxconst[s] > 0 or s = STAGE:NUMBER { // Only rocket engine
                       SET s TO s +1.
                   }
                   IF oxconst[s] = 0 {
                       LOG "No consumer found for "+r:NAME TO "0:estagedat.log".
                   }
                   SET oxmast[s] to oxmast[s] + r:DENSITY*r:AMOUNT.
                } ELSE IF r:NAME = "SolidFuel" {
                   LOCAL s IS lst.
                   UNTIL soconst[s] > 0 or s = STAGE:NUMBER { // Only SRBs
                       SET s TO s +1.
                   }
                   IF soconst[s] = 0 {
                       LOG "No consumer found for "+r:NAME TO "0:estagedat.log".
                   }
                   SET somast[s] to somast[s] + r:DENSITY*r:AMOUNT.
                } ELSE IF r:NAME = "XenonGas" {
                   LOCAL s IS lst.
                   UNTIL xeconst[s] > 0 or s = STAGE:NUMBER { // Only ion drives
                       SET s TO s +1.
                   }
                   IF xeconst[s] = 0 {
                       LOG "No consumer found for "+r:NAME TO "0:estagedat.log".
                   }
                   SET xemast[s] to xemast[s] + r:DENSITY*r:AMOUNT.
                } ELSE {
                    // All other tank content is added to the regular mass
                    IF dbg { LOG "Resource added to regular mass: "+r:NAME TO "0:estagedat.log". }
                    SET pmass TO pmass + r:DENSITY*r:AMOUNT.
                }
            }
        }
        
        // Set regula mass to kst stage
        SET stmass[kst] TO stmass[kst] + pmass. 
    }

    // This lists the mass for fuel and parts when they become activated.
    // This doesn't mean the fuel is burned in this stage. See below.
    IF dbg {
        LOG "" TO "0:estagedat.log".
        LOG "Mass per stage" TO "0:estagedat.log".
        LOG "S,Drymass,LF mass,OX mass,SO mass,XE mass" TO "0:estagedat.log".
        FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
            LOG s+","+nuform(stmass[s],3,3)+","+nuform(lfmast[s],3,3)+","+nuform(oxmast[s],3,3)
                +","+nuform(somast[s],3,3)+","+nuform(xemast[s],3,3)
                TO "0:estagedat.log".
        }
    }

    // Now loop over the stages from earliest to last and find minimum burn time > 0
    // Use burn time to calculate remaining fuel and carry that over to next stage.
    // Calculate start/end mass per stage
    IF dbg {
        LOG "" TO "0:estagedat.log".
        LOG "Burn duration per fuel and stage" TO "0:estagedat.log".
        LOG "S,     ox,    lfX,   nerv,    so,      xe" TO "0:estagedat.log".
    }
    FROM {local s is STAGE:NUMBER.} UNTIL s < 0 STEP {set s to s-1.} DO {
        // Because NERV and LFOX engines both use LF, the combined burn time is:
        LOCAL lfXcon TO lfconst[s]+oxconst[s]*ox2lf. // Consumption LFOX and NERVs
        LOCAL lfXburn IS CHOOSE 0 IF lfXcon = 0 ELSE lfmast[s]/lfXcon.
        LOCAL nervburn IS 0.
        LOCAL oxburn IS CHOOSE 0 IF oxconst[s] = 0 ELSE oxmast[s]/oxconst[s].
        LOCAL soburn IS CHOOSE 0 IF soconst[s] = 0 ELSE somast[s]/soconst[s].
        LOCAL xeburn IS CHOOSE 0 IF xeconst[s] = 0 ELSE xemast[s]/xeconst[s].
        LOCAL oxleft IS 0.
        LOCAL lfleft IS 0.
        // No SRB fuel leftover. Just burns away.
        LOCAL xeleft IS 0.

        // Before sorting RE vs Nerv
        IF dbg {
            LOG s+","+nuform(oxburn,4,2)+nuform(lfXburn,4,2)+","+nuform(nervburn,4,2)
                +","+nuform(soburn,4,2)+","+nuform(xeburn,5,2) TO "0:estagedat.log".
        }
        // Check if we have a NERV
        IF lfconst[s] > 0 { // With NERV
            IF oxconst[s] > 0 {
                // NERV & Rocket
                IF oxburn > 0 AND ABS(lfXburn/oxburn-1) < 0.001 { // Close enough
                    // Matched within 0.1% for NERV and RE
                    SET nervburn TO oxburn.
                } ELSE IF oxburn > lfXburn {
                    SET oxburn TO lfXburn. // Not enough LF, shorten burn
                    SET nervburn TO lfXburn.
                    // Oxygen leftover
                    SET oxleft TO oxmast[s] - oxconst[s]*lfXburn.
                } ELSE { // oxburn < lfXburn
                    // Keep oxburn for RE
                    // Calculate NERV burn
                    LOCAL nervmass IS lfmast[s] - oxburn*oxconst[s]*ox2lf.
                    SET nervburn TO nervmass/lfconst[s].
                }
            } ELSE {
                // Only NERV
                SET nervburn TO lfXburn..
            }
        } ELSE IF oxconst[s] > 0 { // Only RE
            IF oxburn > 0 AND ABS(lfXburn/oxburn-1) < 0.001 { // Close enough
                // Matched within 0.1%
                // Keep oxburn
            } ELSE IF oxburn > lfXburn {
                // More OX than LF
                SET oxburn TO lfXburn.
                // Oxygen leftover
                SET oxleft TO oxmast[s] - oxconst[s]*lfXburn.
            } ELSE {
                // More LF than OX
                // Keep oxburn
                // LF leftover
                SET lfleft TO lfmast[s] - lfXcon*oxburn.
            }
        }
        // After sorting RE vs Nerv
        IF dbg {
            LOG "  "+nuform(oxburn,4,2)+nuform(lfXburn,4,2)+","+nuform(nervburn,4,2)
                +","+nuform(soburn,4,2)+","+nuform(xeburn,5,2) TO "0:estagedat.log".
        }
        
        // Move unused fuel to the next stage if XXcon2st is > 0. This implies that a staging event
        // happens when the shortest burn is over. Likely true for SRBs, questionable otherwise.

        // Count the fuel types used
        LOCAL fueltypes IS 0.
        IF oxburn > 0 { SET fueltypes TO fueltypes+1. }
        IF soburn > 0 { SET fueltypes TO fueltypes+1. }
        IF nervburn > 0 { SET fueltypes TO fueltypes+1. }
        // Ion drives are not considered here. Don't mix them!
        LOCAL stburn IS 0.
        // Heuristic:
        // TODO: These rules might need extension, for example for xeburn > ...
        // If socon2st[s-1] > 0 and soburn > other burn move fuel
        IF fueltypes>1 and s>1 and socon2st[s-1] > 0 and soburn > lfXburn {
            PRINT "Extend SRB burn.".
            SET somast[s-1] TO somast[s] - lfXburn*soconst[s].
            SET somast[s] TO lfXburn*soconst[s].
            SET stburn TO lfXburn.
        }
        LOCAL lfmaused IS 0.
        // If oxcon2[s-1] > 0 and oxburn > other burn move fuel
        IF fueltypes>1 and s>1 and oxcon2st[s-1] > 0 and oxburn > soburn {
            //PRINT s+"Extend LFOX burn.".
            SET lfmaused TO lfmaused + soburn*oxconst[s]*ox2lf.
            SET oxmast[s-1] TO oxmast[s] - soburn*oxconst[s].
            SET oxmast[s] TO soburn*oxconst[s].
            SET oxconst[s-1] TO oxcon2st[s-1]. //Extend burn
            SET stburn TO soburn.
        }
        // If lfcon2[s-1] > 0 and nervburn > other burn move fuel
        IF fueltypes>1 and s>1 and lfcon2st[s-1] > 0 and nervburn > soburn {
            //PRINT s+"Extend NERV burn.".
            SET lfmaused TO lfmaused + soburn*lfconst[s].
            SET lfconst[s-1] TO lfcon2st[s-1]. //Extend burn NERV
            SET stburn TO soburn.
        }
        // Collected LF used
        IF lfmaused > 0 {
            SET lfmast[s-1] TO lfmast[s] - lfmaused.
            SET lfmast[s] TO lfmaused.
        }
        // No fuel carryover to next stage, i.e. the rest might be unburned.
        IF stburn = 0 {
            // IF stburn was set, we moved leftovers to the next stage
            // Xenon is not considered ATM.
            SET lfleftst[s] TO lfleft.
            SET oxleftst[s] TO oxleft.
            //IF oxleft > 0 { PRINT s+" Oxygen left: "+oxleft. }
            //IF lfleft > 0 { PRINT s+" LF left: "+lfleft. }
            SET stburn TO max(lfXburn,max(oxburn,max(soburn,xeburn))).
        } 
        //PRINT s+" Stage burn: "+stburn.
        SET burnst[s] TO stburn.
    }
    // This lists the mass for fuel when they are used. The "leftover" part is unused
    // and will be lost during staging.
    IF dbg {
        LOG "" TO "0:estagedat.log".
        LOG "Fuel used and leftover per stage" TO "0:estagedat.log".
        LOG "S,LF mass,LF left,OX mass,OX left,SO mass,SO left,XE mass,XE left" TO "0:estagedat.log".
        FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
            LOG s+","+nuform(lfmast[s],3,3)+","+nuform(lfleftst[s],3,3)
                +","+nuform(oxmast[s],3,3)+","+nuform(oxleftst[s],3,3)
                +","+nuform(somast[s],3,3)+","+nuform(0,3,3)
                +","+nuform(xemast[s],3,3)+","+nuform(xeleftst[s],3,3)
                TO "0:estagedat.log".
        }
    }

    // Final loop, calculated cumulative mass and other derived values, like
    // start/end TWR, ISP, dV, thrust, burntime
    LOCAL startmass IS 0.
    LOCAL endmass IS 0.

    LOCAL sinfo IS LEXICON().

    IF dbg {
        LOG "" TO "0:estagedat.log".
        LOG "Summary readout per stage" TO "0:estagedat.log".
        LOG "S,  SMass,  EMass,StagedM,BurnedM, Fuleft, Thrust,   ISP,    sTWR,   eTWR,     dv, KSP dv,  btime" TO "0:estagedat.log".
    }
    FROM {local s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
        LOCAL prevstartmass IS startmass. // Technically the next startmass because we start at stage 0
        LOCAL fuleft TO lfleftst[s] + oxleftst[s] + xeleftst[s].
        LOCAL fuburn TO lfmast[s] + oxmast[s] + somast[s] + xemast[s] - fuleft.
        SET endmass TO startmass + stmass[s] + fuleft. // Needs to go before startmass
        SET startmass TO startmass + stmass[s] + fuburn + fuleft.
        LOCAL stagedmass TO CHOOSE endmass - prevstartmass IF s>0 ELSE 0. // Lost when staging the next stage
        LOCAL fucon IS lfconst[s]+oxconst[s]*20/11+soconst[s]+xeconst[s]. // Only XXconst indicates fuel usage
        LOCAL ispg0 IS 0.
        LOCAL thru IS lfthrust[s]+oxthrust[s]+sothrust[s]+xethrust[s].
        IF fucon > 0 {
            SET ispg0 TO thru/fucon/CONSTANT:g0.
        }
        LOCAL sTWR TO thru/startmass/CONSTANT:g0.
        LOCAL eTWR TO thru/endmass/CONSTANT:g0.
        LOCAL dv TO ispg0*CONSTANT:g0*LN(startmass/endmass).

        SET sinfo["SMass"] TO startmass.
        SET sinfo["EMass"] TO endmass.
        SET sinfo["DMass"] TO stagedmass.
        SET sinfo["BMass"] TO fuburn.
        SET sinfo["sTWR"] TO sTWR.
        SET sinfo["eTWR"] TO eTWR.
        SET sinfo["Ft"] TO thru.
        SET sinfo["ISPg"] TO ispg0.
        SET sinfo["dv"] TO dv.
        SET sinfo["dur"] TO burnst[s].
        
        SET sinfolist[s] TO sinfo:COPY. // Make a copy

        IF dbg {
            LOG s+","+nuform(startmass,3,3)+","+nuform(endmass,3,3)+","+nuform(stagedmass,3,3)
                +","+nuform(fuburn,3,3)+","+nuform(fuleft,3,3)+","+nuform(thru,4,2)+","
                +nuform(ispg0,4,2)+","+nuform(sTWR,3,3)+","+nuform(eTWR,3,3)+","
                +nuform(dv,5,1)+","+nuform(SHIP:STAGEDELTAV(s):CURRENT,5,1)+","+nuform(burnst[s],5,1)
            TO "0:estagedat.log".
        }
    }

    RETURN sinfolist.
}
