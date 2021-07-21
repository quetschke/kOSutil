// sinfo.ks - Collect stage stats. Walk the tree starting from an engine recursively
// Copyright © 2021 V. Quetschke
// Version 0.6, 07/20/2021
@LAZYGLOBAL OFF.

// Enabling dbg will create a logfile (0:estagedat.log) that can be used for
// improving and debugging the script.
//LOCAL dbg TO TRUE.
LOCAL dbg TO FALSE.

RUNONCEPATH("libcommon").

// Collect stage stats

// stinfo([atmo]) description
// stinfo takes the following (optional) parameter:
//   atmo:  Determinest atmostpheric pressure used.
//     any non scalar   (default) Any non number value sets pressure to the current pressure.
//     0 to 100         A numeric value of zero to 100 sets the atmostpheric pressure
// The functions returns:
// On failure: 0
// On success: A list of lexicons with one entry per stage with the following information:
//  returnvar[stage]:key with the following defined keys values:
//   SMass   .. startmass
//   EMass   .. endmass.
//   DMass   .. stagedmass.
//   BMass   .. fuel burned
//   sTWR    .. start TWR
//   maxTWR  .. max TWR
//   sSLT    .. start SLT (Sea level thrust)
//   maxSLT  .. max SLT
//   FtV     .. thrust in vacuum
//   FtA     .. thrust at atmospheric pressure
//   KSPispV .. ISPg0 KSP - vacuum
//   KERispV .. ISPg0 Kerbal Engineer Redux - vacuum
//   KSPispA .. ISPg0 KSP - at atmospheric pressure
//   KERispA .. ISPg0 Kerbal Engineer Redux - at atmospheric pressure
//   VdV     .. Vacuum delta V
//   AdV     .. Atmospheric delta V (see atmo parameter)
//   dur     .. burn duration
// The following key is the same for all stages:
//   ATMO    .. Atmospheric pressure used for thrust calculation

// Staging - For stages with decouplers, KSP assumes it immediately stages after all
// active engines connected to this decoupler are out of all available fuel.

// General structure
// This script determines the fuel per engine, or engine group (more about this below.)
// Stage numbering:
// x Stages are counted from the current stage (STAGE:NUMBER) to 0. A value -1 is
//   possible and means never decoupled or never activated.
// x part:DECOUPLEDIN The part is considered part of the vessel until this value is
//   reached. We use
//     lst = part:DECOUPLEDIN-1 (last stage)
//   to track the stage when the part is still counted for the mass.
// x part:STAGE The part gets staged/activated. ast = part:STAGE.
//
// The scrip tries to get a stage listing like KER/MJ, with:
// "start mass, end mass, staged/dropped mass, burned fuel, TWR s/e, thrust, ISPg0, DV, duration"
//
// Some variables use futype as an array. With
//   enum fu = {0=LiquidFuel, 1=Oxidizer, 2=SolidFuel, 3=XenonGas}
//
// Global variables with stage (st) info:
//   stmass[st] Drymass in stage
//   sticon[st] Initial fuel consumption in stage. This is based on the consumption at the beginning
//              of the stage, but during sub-stages (when different maximum burn durations for engine
//              groups exist) the consumption can changes. See sub[s][i]:XX variables below.
//              Can be used to calculate kspISPg0. kerISPg0 is slightly different.
//   stithruV[st] Initial vac thrust in stage. Same reasoning as for sticon[st].
//   stithruA[st] Initial atmospheric thrust in stage. Same reasoning as for sticon[st].
//   stburn[st] Burn duration of stage
//   stfuel[st] Fuel in stage
//   stleft[st] Unburned left fuel in stage
//   
// This is done in several passes:
// 1. First the script loops over all engines to create engine groups (eg). An eg is
//    attached to the same fuel reservoir (connected tanks).
//    Each eg keeps the following information in the form eg[idx]:key:
//      egli    List of parts in eg
//      egtali  Holds all tanks and engines from engine group.
//      egflli  Holds all fuel line parts from engine group.
//      egastage Stage when eg becomes active
//      egdstage Stage when eg is decoupled
//      The following variables are used:
//      con[eg][st][fu]   Fuel consuption in eg, by stage and fuel
//      thruV[eg][st][fu]  Thrust in eg, by stage and fuel
//      thruA[eg][st][fu]  Thrust in eg, by stage and fuel
//      fma[eg][st][fu]   Fuel mass in eg, by stage and fuel
//      flt[eg][st][fu]   Fuel mass left in eg, by stage and fuel
//      burn[eg][st][fu]  Burn time in eg, by stage and fuel
//    As each eg is actually subdivided in fu groups by fuel, we sometime use fuel engine group (fueg) to
//    describe the possible fuel dependent engine groups that use different fuels and can have different
//    burn durations within one engine group.
//    Note:
//    We use some trickery to distinguish Rocket Engines for nuclear fuel engines. Rocket engines
//    use 9u LF per 11u OX. NERV engines use only LF. Both have a density of 0.005t/u.
//    Store rocket engines fuel only under OX and NERV fuel under LF.
//    Some 
//
// 2. Loop over all parts
//    x Check for parts not connected to an eg. (For fun)
//    x Add all drymass (non consumables) to the last stage where mass is
//      counted (p:DECOUPLEDIN+1).
//    x Correct for fairing panel mass
//    x Add fuel from tanks not in engine groups to stage mass. Also add fuel that is not used by
//      the supported engines (fuli[]).
//
// 3. Loop over engine groups and check for fuel ducts.
//    Note: Not supported yet.
//    The plan is to create a list of all eg that deliver fuel to an eg.
//    Then calculate the burn times for the source and target egs. Needs further thought.
//
// 4. Loop over engine groups to collect consumption, thrust and fuel mass.
//
// 5. Calculate burn duration for egs, for all fuels. Look for the maximum duration of decoupled stages,
//    if it doesn't exist, use the overall maximum burn time for the stage. Move fuel if the maximum
//    decoupled stage burn time is shorter than the maximum non-decoupled stage burn time..
//
// 6. Initialize sub-stages burn info in sub[s][i]:XX with XX = bt, eg, fu, bt2, con, thru.
//    Note: Explain!
//
// 7. Finally calculate mass, ISP, dV, thrust, TWR, burntime

DELETEPATH("0:sinfo.log").

//stinfo().
// End of program!

// Functions
FUNCTION mLog {
    PARAMETER s,    // String
            t IS 3. // 1 = LOG, 2 = PRINT, 3 = Both
    
    // TODO: Use t
    LOG s TO "0:sinfo.log".
    PRINT s.
    
    RETURN 1.
}

FUNCTION stinfo {
    PARAMETER atmo IS "current". // Select atmostphere pressure - in atmospheres.
                                 // A numeric value of zero or larger is used as pressure.
                                 // Anything else means use current pressure.

    // Initialize a list of zeroes.
    LOCAL stZ TO LIST().
    FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
      stZ:ADD(0).
    }
    LOCAL stmass TO stZ:COPY.
    LOCAL sticon TO stZ:COPY.
    LOCAL stithruV TO stZ:COPY.
    LOCAL stithruA TO stZ:COPY.
    LOCAL stburn TO stZ:COPY.
    LOCAL stfuel TO stZ:COPY.
    LOCAL stleft TO stZ:COPY.
    
    LOCAL sinfolist TO stZ:COPY. // List to store the stage info

    // 9lf to 11ox is the Kerbal rocket fuel relationship. Set that as a const.
    LOCAL ox2lf TO 9.0/11.0.

    LOCAL procli TO LIST(). // Holds all processed parts.
    LOCAL egli TO LIST(). // Holds all engine group parts.
    LOCAL egtali TO LIST(). // Holds all tanks and engines from engine group.
    LOCAL egflli TO LIST(). // Holds all fuel line parts from engine group.
    LOCAL egastage TO 999. // Use this as the stage the current engine group becomes active
    LOCAL egdstage TO 999. // The stage when current engine has been removed

    LOCAL prili TO LIST("Decoupler","Engine").
    LOCAL nocflist TO LIST("I-Beam", "Strut Connector", "Structural Panel").
    // The list of fuels known to this script. Might grow for newer versions or mods
    LOCAL fuli TO LIST("LiquidFuel", "Oxidizer", "SolidFuel", "XenonGas").
    // We use the variables to identify LF and OX.
    LOCAL LFidx TO fuli:FIND("LiquidFuel").
    LOCAL OXidx TO fuli:FIND("Oxidizer").
    LOCAL fuCorr TO LIST(1, 1, 1, 1).
    // Used to correct stmass[] for LF in REs. 
    SET fuCorr[OXidx] TO 20/11.
    LOCAL fuliZ TO LIST(0,0,0,0). // Placeholder for fuel types

    // Will be initialized after eg loop to:
    LOCAL con TO LIST().  // con[eg][st][fu]   Fuel consuption in eg, by stage and fuel
    LOCAL thruV TO LIST(). // thruV[eg][st][fu]  Vac thrust in eg, by stage and fuel
    LOCAL thruA TO LIST(). // thruA[eg][st][fu]  Atmospheric thrust in eg, by stage and fuel
    LOCAL fma TO LIST().  // fma[eg][st][fu]   Fuel mass in eg, by stage and fuel
    LOCAL flt TO LIST().  // flt[eg][st][fu]   Fuel mass left in eg, by stage and fuel
    LOCAL burn TO LIST(). // burn[[eg][st][fu] Burn time in eg, by stage and fuel

    // 1. First the script loops over all engines to create engine groups (eg)
    LOCAL elist TO -999. LIST ENGINES IN elist.

    IF dbg { mLog("p:DECOUPLEDIN,p:STAGE,p:TITLE,p:NAME,p:TYPENAME,lvl"). }
    LOCAL egidx TO 0.
    LOCAL eg TO LIST().
    FOR e IN elist {
        // To process fuel flow correctly start with the engines with the earliest decoupling

        SET egastage TO e:STAGE. // Use this as the stage the current engine group becomes active
        SET egdstage TO e:DECOUPLEDIN. // The stage when current engine has been removed
        SET egli TO LIST(). // Collect engine group list
        SET egtali TO LIST(). // Holds all tanks and engines from engine group.
        SET egflli TO LIST(). // Holds all fuel line parts from engine group.

        IF eTree(e,0) { // Find the engine group where this engine belongs to.
            // Successfully returned
            IF dbg { mLog("Found eg: "+egidx). }
            eg:ADD(0).
            SET eg[egidx] TO LEXICON().
            SET eg[egidx]["egli"] TO egli.
            SET eg[egidx]["egtali"] TO egtali.
            SET eg[egidx]["egflli"] TO egflli.
            SET eg[egidx]["egastage"] TO egastage.
            SET eg[egidx]["egdstage"] TO egdstage.

            SET egidx TO egidx+1.
        } ELSE {
            // This engine is already part of another eg.
            BREAK.
        }
        IF dbg { mLog(" "). }
    }

    // 2. Now loop over all parts
    LOCAL plist TO -999. LIST PARTS IN plist.
    IF dbg { mLog("kst,p:DECOUPLEDIN,p:STAGE,p:TITLE,p:TYPENAME,p:MASS,p:DRYMASS,fuel,ineg"). }
    FOR p IN plist {
        LOCAL ineg TO 1.
        IF NOT procli:CONTAINS(p:UID) {
            // List the ones we missed.
            SET ineg TO 0.
        }
        LOCAL lst is p:DECOUPLEDIN+1.  // Last stage where mass is counted
        LOCAL ast is p:STAGE.  // Stage where part is activated
        LOCAL kst is lst.  // Stage number like in KER/MJ

        LOCAL pmass IS p:DRYMASS. // Fairings change mass. Need this as variable

        IF p:TYPENAME = "LaunchClamp" { SET pmass TO 0. } // Ignore mass of clamps.

        IF p:TYPENAME = "Decoupler" {
            // Decouplers have only mass prior to being activated, they stay on without mass
            SET kst TO ast+1.
        }

        // Fairings need special treatment
        // Todo: Use lexicon.
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
                // When not staged panel and base mass automatically get added to the same stage.
                // (ast+1 = lst)
            }
        }

        // Special treatment for fuel tanks/boosters.
        IF p:MASS > p:DRYMASS {
            FOR r IN p:RESOURCES {
                IF NOT fuli:CONTAINS(r:NAME) OR NOT procli:CONTAINS(p:UID){
                    // All non fuel tank content or tank content not in an eg is added to the regular mass
                    IF dbg { mLog("Resource added to regular mass: "+r:NAME). }
                    SET pmass TO pmass + r:DENSITY*r:AMOUNT.
                }
            }
        }
        
        // Set regular mass to kst stage
        SET stmass[kst] TO stmass[kst] + pmass.
        // Log the part
        IF dbg { mLog(kst+","+p:DECOUPLEDIN+","+p:STAGE+","+p:TITLE+","+p:TYPENAME+","
             +p:MASS+","+p:DRYMASS+","+(p:MASS-p:DRYMASS)+","+ineg). }
    }


    // 3. Loop over engine groups
    IF dbg { mLog(" "). }
    FROM {LOCAL i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
        // Initialize variables 3-D lists for all eg:
        con:ADD(stZ:COPY).  // Consumption - Now con[eg][st]
        thruV:ADD(stZ:COPY). // Thrust vacuum
        thruA:ADD(stZ:COPY). // Thrust atmospheric pressure
        fma:ADD(stZ:COPY).  // Fuel mass
        flt:ADD(stZ:COPY).  // Fuel mass left
        burn:ADD(stZ:COPY). // Burn time
        FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
            SET con[i][s] TO fuliZ:COPY.   // Now [eg][st][fu]
            SET thruV[i][s] TO fuliZ:COPY.  // Now [eg][st][fu]
            SET thruA[i][s] TO fuliZ:COPY.  // Now [eg][st][fu]
            SET fma[i][s] TO fuliZ:COPY.   // Now [eg][st][fu]
            SET flt[i][s] TO fuliZ:COPY.   // Now [eg][st][fu]
            SET burn[i][s] TO fuliZ:COPY.  // Now [eg][st][fu]
        }

        // Check where fuel lines go.
        // Note: This doesn't do anything yet.
        FOR fl IN eg[i]:egflli {
            LOCAL pa TO fl:DECOUPLER:PARENT.
            LOCAL ch TO fl:DECOUPLER:CHILDREN[0].
            LOCAL fulinetarget TO pa.
            IF eg[i]:egli:CONTAINS(pa) {
                // Decoupler parent is in current eg.
                SET fulinetarget TO ch.
            }
            // Decoupler child is in current eg.
            LOCAL fltarget TO -1.
            FROM {LOCAL x IS 0.} UNTIL x >= eg:LENGTH STEP {SET x to x+1.} DO {
                IF eg[x]:egli:CONTAINS(fulinetarget) {
                    SET fltarget TO x.
                    BREAK.
                }
            }
            IF dbg { mLog("Eg "+i+" has fuel line connected to eg: "+fltarget+"."). }
        }
    }


    // 4. Loop over engine groups - again
    IF dbg {
        mLog(" ").
        mLog("eg,egast,egdst,parts,entas").
    }
    FROM {local i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
        // This could be combined with the previous loop, but this way it is easier to follow.
        IF dbg {
            mLog(i+","+eg[i]:egastage+","+eg[i]:egdstage+","+eg[i]:egli:LENGTH+","+eg[i]:egtali:LENGTH). }

        // Loop over tanks and engines
        // We use some trickery to distinguish Rocket Engines for nuclear fuel engines. Rocket engines
        // use 9u LF per 11u OX. NERV engines use only LF. Both have a density of 0.005t/u.
        // Store rocket engines only under OX and NERV under LF.
        FOR x in eg[i]:egtali {
            IF x:TYPENAME = "Engine" {
                // conF, thruVF and thruAF hold consumption and thrust for the current engine. This makes
                // the special RE and NERV treatment a little easier.
                LOCAL conF TO fuliZ:COPY. // Storage for current engine for fuel consumption
                LOCAL thruVF TO fuliZ:COPY. // Storage for current engine for thrust
                LOCAL thruAF TO fuliZ:COPY. // Storage for current engine for thrust
                // Use thrust in vacuum and at current position.
                LOCAL pthrustvac IS x:POSSIBLETHRUSTAT(0). // Vacuum thrust. Includes thrust limit setting.
                LOCAL pthrustcur IS x:POSSIBLETHRUST. // Current thrust. Includes thrust limit setting.
                // Use parameter atmo to control atmospheric pressure used to calculate thrust.
                IF atmo:ISTYPE("Scalar") {
                    IF atmo < 0 {
                        mLog(" ").
                        mLog("Invalid argument: pressure "+ROUND(atmo,3)+" less than zero").
                        mLog(" ").
                        RETURN 0.
                    }
                    IF atmo > 100 {
                        mLog(" ").
                        mLog("Invalid argument: pressure "+ROUND(atmo,3)+" greater than 100 atm").
                        mLog(" ").
                        RETURN 0.
                    }
                    SET pthrustcur TO x:POSSIBLETHRUSTAT(atmo).
                } ELSE {
                    SET atmo TO "current pressure".
                }
                
                LOCAL tlimit IS x:THRUSTLIMIT/100. // Needed to adjust res:MAXFUELFLOW
                IF dbg { mLog("Engine: "+x:TITLE). }
                FOR fkey IN x:CONSUMEDRESOURCES:KEYS { // fkey is language localized display name
                    LOCAL cRes TO x:CONSUMEDRESOURCES[fkey]. // Consumed resource
                    LOCAL fname TO cRes:NAME. // Workaround for bug. fname not localized (language)
                    LOCAL fti TO fuli:FIND(fname).
                    // Sanity check if our engine consumes something else than fuli
                    IF fti >= 0 {
                        // Set con[fti]
                        SET conF[fti] TO cRes:MAXFUELFLOW*cRes:DENSITY*tlimit.
                        SET thruVF[fti] TO pthrustvac.
                        SET thruAF[fti] TO pthrustcur.
                    } ELSE IF fname = "ElectricCharge" {
                        // Has no mass - ignored
                    } ELSE {
                         // RCS thrusters are not engines, this cannot be triggered by momopropellant.
                        IF dbg { mLog("Found unknown fuel "+fname+" - investigate!"). }
                        PRINT 1/0.
                    }
                }
                // Special treatment for REs.
                IF conF[LFidx]*conF[OXidx] > 0 {
                    // Rocket engine - remove LF thrust and consumption from REs.
                    // LF consumption is included below with fuCorr[].
                    SET conF[0] TO 0.
                    SET thruVF[0] TO 0.
                    SET thruAF[0] TO 0.
                }
                    
                // Now add fuel to the applicable stages. This also adds the LF mass consumption for REs.
                FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
                    IF s <= x:STAGE AND s > x:DECOUPLEDIN {
                        // Add values cumulatively.
                        FROM {LOCAL x IS 0.} UNTIL x >= fuli:LENGTH STEP {SET x TO x+1.} DO {
                            SET con[i][s][x] TO con[i][s][x] + conF[x].
                            SET thruV[i][s][x] TO thruV[i][s][x] + thruVF[x].
                            SET thruA[i][s][x] TO thruA[i][s][x] + thruAF[x].
                            // Also add stage cumulative values.
                            SET sticon[s] TO sticon[s] + conF[x]*fuCorr[x]. // Correct for OX use.
                            SET stithruV[s] TO stithruV[s] + thruVF[x].
                            SET stithruA[s] TO stithruA[s] + thruAF[x].
                        }
                    } ELSE {
                        // Add zeroes
                        SET con[i][s] TO fuliZ:COPY.
                        SET thruV[i][s] TO fuliZ:COPY.
                        SET thruA[i][s] TO fuliZ:COPY.
                    }
                }
            }
            // Part with fuel (Tank or SRB)
            IF x:MASS > x:DRYMASS {
                FOR r IN x:RESOURCES {
                    LOCAL fti TO fuli:FIND(r:NAME).
                    IF fti >= 0 {
                        // Fuel in fma[] will be added to stfuel[] later.
                        SET fma[i][eg[i]:egastage][fti] TO fma[i][eg[i]:egastage][fti] + r:AMOUNT*r:DENSITY.
                    } // Fuel not in fuli has been added to stmass[] already.
                }
            }
        }
    }


    // Print/Log consumption, thrust and mass info for all egs, s and f
    egLog().

    // 5. Calculate burn durations for engine groups, for all fuels.
    // Loop over stage, loop over eg, check if eg has consumption at stage.
    // Calc burn duration for each fuel type, find maximum burn time for the
    // engine group.
    // If all active eg in the current stage, with a decoupler in the next stage,
    // run out of fuel "stage" and move the remaining fuel in any active eg to
    // the next stage. (unburned fuel to next stage.) 
    FROM {LOCAL s IS STAGE:NUMBER.} UNTIL s < 0 STEP {SET s TO s-1.} DO {
        LOCAL maxBDecEg TO 0. // Max burn decoupled eg
        LOCAL maxBRemEg TO 0. // Max burn remaining eg
        LOCAL egBurn TO LIST(). // Burn duration for eg
        IF dbg {
            mLog(" ").
            mLog("St "+s+" eg burn info:").
            LOCAL sstring TO "S".
            FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                SET sstring TO sstring+","+fuli[f].
            }
            mLog(sstring).
        }
        // Find burn durations
        FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
            // First calculate burn time per eg and fuel type at this stage.
            IF s <= eg[e]:egastage AND s > eg[e]:egdstage { // Only consider active egs
                LOCAL BurnV TO 0.
                LOCAL sburn TO "".
                FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                    // BurnV for LF is wrong when RE is present. Fixed below.
                    SET BurnV TO CHOOSE 0 IF con[e][s][f] = 0 ELSE fma[e][s][f] / con[e][s][f].
                    SET burn[e][s][f] TO BurnV.
                    IF dbg { SET sburn TO sburn + ","+nuform(burn[e][s][f],3,2). }
                }
                IF dbg { mLog(e+sburn). }
            }
        }
        // Correct for RE vs. NERV fuel and oxidizer usage
        FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
            // Now correct the burn times for RE and NERV.
            LOCAL mBurnV TO 0.
            IF s <= eg[e]:egastage AND s > eg[e]:egdstage {
                LOCAL LFXcon TO con[e][s][LFidx] + con[e][s][OXidx]*ox2lf.
                // Combined NERV and RE LF based burn.
                LOCAL LFXburn TO CHOOSE 0 IF LFXcon = 0 ELSE fma[e][s][LFidx]/LFXcon.
                LOCAL OXburn TO burn[e][s][OXidx]. // Recalulated below
                LOCAL LFburn TO burn[e][s][LFidx]. // Recalulated below - certainly wrong when RE present
                IF dbg { mLog("eg:"+e+", burn bef. corr: LFX: "+ROUND(LFXburn,1)+" LF: "+ROUND(LFburn,1)+" OX: "+ROUND(OXburn,1)). }
                IF LFXburn < OXburn {
                    // Shorten OXburn
                    SET OXburn TO LFXburn. // Less LF than OX for RE (OX leftover)
                    SET burn[e][s][OXidx] TO OXburn.
                }
                // No need to treat the case of OXburn < LFXburn. The Nerv burn is recalculated based
                // on the OXburn anyway.
                // If a NERV is present, no leftover. Otherwise this case covers for RE with less
                // OX than LF. This leads to LF leftover and a LFburn of 0s.
                // Recalculate LFburn, with RE in mind
                SET LFburn TO CHOOSE 0 IF con[e][s][LFidx] = 0 ELSE
                    (fma[e][s][LFidx] - OXburn*con[e][s][OXidx]*ox2lf) / con[e][s][LFidx]. // No leftover
                SET burn[e][s][LFidx] TO LFburn.
                IF dbg { mLog("eg:"+e+", burn aft. corr: LFX: "+ROUND(LFXburn,1)+" LF: "+ROUND(LFburn,1)+" OX: "+ROUND(OXburn,1)). }
                
                // Find maximum values
                FROM {local f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                    IF burn[e][s][f] > mBurnV { SET mBurnV TO burn[e][s][f]. }
                }
                // Max burn for decoupled stage and remaining stages
                IF eg[e]:egdstage+1 = s {
                    //IF dbg { mLog(s+","+e+" Gets decoupled."). }
                    SET maxBDecEg TO MAX(maxBDecEg,mBurnV).
                } ELSE {
                    //IF dbg { mLog(s+","+e+" Move fuel."). }
                    SET maxBRemEg TO MAX(maxBRemEg,mBurnV).
                }
            }
            egBurn:ADD(mBurnV).
        }
        // Maximum burn time of stages with decoupler.
        SET stburn[s] TO maxBDecEg.
        // If nothing decouples, use maximum burn time.
        IF stburn[s] = 0 { SET stburn[s] TO maxBRemEg. }

        // Work on burn duration
        FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
            // Now check how much fuel gets transfered.
            IF s <= eg[e]:egastage AND s > eg[e]:egdstage {
                IF eg[e]:egdstage+1 = s {
                    // This eg gets decoupled (or is the last one). Check for leftover fuel - gets dropped.
                    IF dbg { mLog("Gets decoupled - eg: "+e+" burn: "+ROUND(egBurn[e],2)+" s."). }
                    FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {SET f to f+1.} DO {
                        LOCAL FuBurned TO burn[e][s][f] * con[e][s][f].
                        IF f = LFidx { // Inlude LF from REs
                            SET FuBurned TO FuBurned + burn[e][s][OXidx]*con[e][s][OXidx]*ox2lf.
                        }
                        SET flt[e][s][f] TO fma[e][s][f] - FuBurned.
                        SET fma[e][s][f] TO FuBurned.
                        // Leftover fuel gets dropped with the stage.
                        SET stleft[s] TO stleft[s] + flt[e][s][f].
                    }
                } ELSE {
                    // This eg remains. Adjust the burn duration, check for leftover fuel and move it to
                    // the next stage.
                    IF dbg { mLog("Stays - eg: "+e+" burn: "+ROUND(egBurn[e],2)
                            +" move "+ROUND(egBurn[e] - maxBDecEg,2)+" s fuel."). }
                    FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {SET f to f+1.} DO {
                        // Adjust burn duration for fueg
                        IF burn[e][s][f] > maxBDecEg {
                            SET burn[e][s][f] TO maxBDecEg.
                        }
                        LOCAL burnDur TO burn[e][s][f].
                        LOCAL FuBurned TO burnDur * con[e][s][f].
                        IF f = LFidx { // Inlude LF from REs
                            LOCAL burnDurOX TO MIN(stburn[s], burn[e][s][OXidx]).
                            SET FuBurned TO FuBurned + burnDurOX*con[e][s][OXidx]*ox2lf.
                        }
                        // Leftover fuel gets moved to the next stage.
                        SET fma[e][s-1][f] TO fma[e][s][f] - FuBurned.
                        SET fma[e][s][f] TO FuBurned.
                    }
                }

                // Sum up fuel - burned in active stages.
                FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {SET f to f+1.} DO {
                    SET stfuel[s] TO stfuel[s] + fma[e][s][f].
                }
            }
        }
    }

    // Print/Log consumption, thrust and mass info for all egs, s and f after corrections
    egLog().

    // 6. Initialize sub-stages burn info in sub[s][i]:XX with XX =
    // bt .. Total burn duration of engine group (=burn[eg][st][fu])
    // eg .. engine group
    // fu .. fuel type (actually engine type)
    // bt2 .. Burn duration of current substage. This is best explained with an example, lets assume the
    //        current stage has three burn durations, and hence three substages (i=0,1,2):
    //          sub[s][i=0]:bt = burn[0][st][2=SolidFuel] = 1s, (SRBs)
    //          sub[s][i=1]:bt = burn[1][st][1=Oxidizer] = 2s. (Another eg with rocket engines)
    //          sub[s][i=2]:bt = burn[0][st][1=Oxidizer] = 4s, ( Rocket engines)
    //        In the first substage all three fueg are active, in the second substage the second and third
    //        fueg are still on and in the third only the last fueg is still burning.
    //        The substage duration (bt2) is the time that is spent in that substage, with the number of
    //        active fueg. So sub[s][i=0]:bt2 = 1s, sub[s][i=1]:bt2 = 1s, sub[s][i=2]:bt2 = 2s. 
    // con .. Total fuel consumption of the active fueg.
    // thruV .. Total vac thrust of the active fueg.
    // thruA .. Total thrust of the active fueg at atmospheric pressure.
    IF dbg { mLog("-----"). }
    LOCAL sub TO LIST().
    LOCAL lex TO LEXICON().
    // Create sorted sub[s][i]:XX. Sorted in i by shortest to longest burntime of substage (Zero burn
    // durations are omitted). In eg and fu are the indices to find the corresponding con[eg][st][fu],
    // thruV[..], fma[..], flt[..] and burn[..] values.
    // Burn[..] is also stored in sub[s][i]:bt.
    FROM {LOCAL s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
        IF dbg { mLog( "s: "+s). }
        sub:ADD(LIST()).
        FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
            FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {SET f to f+1.} DO {
                IF dbg { mLog(burn[e][s][f]). }
                // Only add info for actual burns. This can leave sub[s] empty.
                IF burn[e][s][f] > 0 {
                    SET lex to LEXICON("bt", burn[e][s][f],
                        "eg", e, "fu", f, "bt2", 0, "con", 0, "thruV", 0, "thruA", 0).
                    LOCAL isinserted TO False.
                    FOR idx IN RANGE(sub[s]:LENGTH) {
                        // iterate through all entries by index
                        // the range is empty if the list is empty
                        IF burn[e][s][f] <= sub[s][idx]:bt {
                            // if burn is shorter, insert
                            // before the current element
                            sub[s]:INSERT(idx,lex:COPY).
                            SET isinserted TO True.
                            BREAK.
                        }
                    }
                    IF NOT isinserted {
                        // if we didn't insert, it goes to the end
                        sub[s]:ADD(lex:COPY).
                    }
                }
            }
        }
        // The maximum burn duration across all eg and fu for this stage is the last entry.
        IF dbg {
            mLog("---").
            mLog("eg,fu,bt,bt2,con,thruV").
        }
        LOCAL pssbd TO 0. // Previous substage burn duration 
        FROM {LOCAL i is 0.} UNTIL i > sub[s]:LENGTH-1 STEP {set i to i+1.} DO {
            // Avoid negative values because of floating point accuracy.
            SET sub[s][i]:bt2 TO MAX(sub[s][i]:bt - pssbd, 0).
            SET pssbd TO sub[s][i]:bt.
            // Sum up consuption and thrust for active fuegs
            IF sub[s][i]:bt > 0 { // Todo: This should always be true!?
                FROM {LOCAL ii is 0.} UNTIL ii > sub[s]:LENGTH-1 STEP {set ii to ii+1.} DO {
                    // TODO: This loop can be improved. Sum from i to sub[s]:LENGTH-1
                    IF sub[s][ii]:bt >= sub[s][i]:bt {
                        LOCAL f TO sub[s][ii]:fu.
                        LOCAL e TO sub[s][ii]:eg.
                        SET sub[s][i]:con TO sub[s][i]:con + fuCorr[f]*con[e][s][f]. // RE corr
                        SET sub[s][i]:thruV TO sub[s][i]:thruV + thruV[e][s][f].
                        SET sub[s][i]:thruA TO sub[s][i]:thruA + thruA[e][s][f].
                    }
                }
                IF dbg { mLog(sub[s][i]:eg+","+sub[s][i]:fu+","+sub[s][i]:bt+","+sub[s][i]:bt2+","
                         +sub[s][i]:con+","+sub[s][i]:thruV). }
            }
        }
        IF dbg { mLog("-----"). }
    }

    // 7. Final loop, calculated cumulative mass and other derived values, like
    // start/end TWR, ISP, dV, thrust, burntime
    LOCAL startmass IS 0.
    LOCAL endmass IS 0.

    LOCAL sinfo IS LEXICON().

    IF dbg {
        mLog(" ").
        mLog("Summary readout per stage / substage").
    }
    FROM {LOCAL s is 0.} UNTIL s > STAGE:NUMBER STEP {set s to s+1.} DO {
        LOCAL prevstartmass IS startmass. // Technically the next startmass because we start at stage 0
        LOCAL fuleft TO stleft[s].
        LOCAL fuburn TO stfuel[s]. // Todo: Could be replaced with stfubu
        SET endmass TO startmass + stmass[s] + fuleft. // Needs to go before startmass
        SET startmass TO startmass + stmass[s] + fuburn + fuleft.
        LOCAL stagedmass TO CHOOSE endmass - prevstartmass IF s>0 ELSE 0. // Lost when staging the next stage
        
        // Calculate delta V per substage
        LOCAL stfubu TO 0. // Cumulative fuel burned in stage
        LOCAL stVdV TO 0.   // Cumulative vacuum delta V in stage
        LOCAL stAdV TO 0.   // Cumulative atmospheric delta V in stage
        LOCAL curmass TO startmass.
        
        LOCAL sTWR TO 0.
        LOCAL sSLT TO 0.
        IF sub[s]:LENGTH > 0 {
            SET sTWR TO sub[s][0]:thruV/startmass/CONSTANT:g0.
            SET sSLT TO sub[s][0]:thruA/startmass/CONSTANT:g0.
        }
        LOCAL maxTWR TO 0.
        LOCAL maxSLT TO 0.

        IF dbg {
            mLog("--------").
            mLog("Stage "+s+" Substages:").
            mLog("i,con,thruV,thruA,ispsV,sfubu,subVdV,subAdV,curmass,submass").
        }
        FROM {LOCAL i is 0.} UNTIL i > sub[s]:LENGTH-1 STEP {set i to i+1.} DO {
            IF sub[s][i]:con > 0 { // Todo: This should always be true!?
                LOCAL fcon TO sub[s][i]:con.
                LOCAL fthruV TO sub[s][i]:thruV.
                LOCAL fthruA TO sub[s][i]:thruA.
                LOCAL ispsV TO fthruV/fcon/CONSTANT:g0.
                LOCAL ispsC TO fthruA/fcon/CONSTANT:g0.
                LOCAL subfubu TO fcon*sub[s][i]:bt2. // Fuel burned in substage
                SET stfubu TO stfubu + subfubu.
                LOCAL submass TO curmass - subfubu. // Mass at end of current substage
                SET maxTWR TO MAX(maxTWR, sub[s][i]:thruV/submass/CONSTANT:g0).
                SET maxSLT TO MAX(maxSLT, sub[s][i]:thruA/submass/CONSTANT:g0).
                LOCAL subVdV TO ispsV*CONSTANT:g0*LN(curmass/submass).
                LOCAL subAdV TO ispsC*CONSTANT:g0*LN(curmass/submass).
                SET stVdV TO stVdV + subVdV.
                SET stAdV TO stAdV + subAdV.
                IF dbg { mLog(i+","+fcon+","+fthruV+","+fthruA+","+ispsV+","+subfubu+","+subVdV
                         +","+subVdV+","+curmass+","+submass). }
                SET curmass TO submass. // The next substage starts with the current substge end mass.
            }
        }
        LOCAL kerispV TO 0. // ISPg0 vac like MJ/KER uses
        LOCAL KERispA TO 0. // ISPg0 sea level like MJ/KER uses
        IF stVdV {
            SET kerispV TO stVdV/CONSTANT:g0/LN(startmass/endmass).
            SET KERispA TO stAdV/CONSTANT:g0/LN(startmass/endmass).
        }
        // Sanity check
        IF stburn[s] > 0 AND ABS(1-stfubu/fuburn) > 0.0001 {
            mLog(" ").
            mLog("Check fuel burned! Substage cumulative: "+stfubu+" Stage: "+fuburn).
            mLog(" ").
        }
        
        LOCAL kspispV IS 0.
        LOCAL KSPispA IS 0.
        LOCAL thruV IS stithruV[s].// Thrust in stage (vacuum).
        LOCAL thruA IS stithruA[s].// Thrust in stage (current position).
        IF fuburn = 0 {
            SET thruV TO 0.
            SET thruA TO 0.
        }
        // Note: We cannot average over different burn times. Use sub-stages by burn time.
        IF sticon[s] > 0 {
            SET kspispV TO thruV/sticon[s]/CONSTANT:g0.
            SET KSPispA TO thruA/sticon[s]/CONSTANT:g0.
        }

        SET sinfo["SMass"] TO startmass.
        SET sinfo["EMass"] TO endmass.
        SET sinfo["DMass"] TO stagedmass.
        SET sinfo["BMass"] TO fuburn.
        SET sinfo["sTWR"] TO sTWR.
        SET sinfo["maxTWR"] TO maxTWR.
        SET sinfo["sSLT"] TO sSLT.
        SET sinfo["maxSLT"] TO maxSLT.
        SET sinfo["FtV"] TO thruV.
        SET sinfo["FtA"] TO thruA.
        SET sinfo["KSPispV"] TO kspispV.
        SET sinfo["KERispV"] TO kerispV.
        SET sinfo["KSPispA"] TO KSPispA.
        SET sinfo["KERispA"] TO KERispA.
        SET sinfo["VdV"] TO stVdV.
        SET sinfo["AdV"] TO stAdV.
        SET sinfo["dur"] TO stburn[s].

        SET sinfo["ATMO"] TO atmo.
        
        SET sinfolist[s] TO sinfo:COPY. // Make a copy

        IF dbg {
            mLog(" ").
            mLog("S,  SMass,  EMass,StagedM,BurnedM, Fuleft,ThrustV,ThrustC,KSPispV,KERispV,   sTWR,"
                 +" maxTWR,   sSLT, maxSLT, vac dv, KSP dv,  btime").

            mLog(s+","+nuform(startmass,3,3)+","+nuform(endmass,3,3)+","+nuform(stagedmass,3,3)
                +","+nuform(fuburn,3,3)+","+nuform(fuleft,3,3)+","+nuform(thruV,4,2)+","
                +nuform(thruA,4,2)+","
                +nuform(kspispV,4,2)+","+nuform(kerispV,4,2)+","+nuform(sTWR,3,3)+","+nuform(maxTWR,3,3)+","
                +nuform(sSLT,3,3)+","+nuform(maxSLT,3,3)+","
                +nuform(stVdV,5,1)+","+nuform(SHIP:STAGEDELTAV(s):VACUUM,5,1)+","+nuform(stburn[s],5,1)
            ).
        }
    }
    IF dbg { mLog("--------"). }

    RETURN sinfolist.
    // End of stinfo

    // Local (nested) functions:
    FUNCTION eTree {
        // This function walks the parts tree recoursively and collects values in
        // egli, egtali, egflli, egastage, egdstage.
        // In procli all parts that have been assigned to an eg will be remembered.
        // The function returns False if the first part it gets called on is already in an engine group.
        PARAMETER p,    // Part node.
                l.      // Recursion level, child increases, parent decreases. Only for info.

        IF procli:CONTAINS(p:UID) {
            //PRINT "Already processed! Skipped ..".
            RETURN False.
        }

        // Todo: Delete after testing - likely unneeded.
        //LOCAL lst is p:DECOUPLEDIN+1.  // Last stage where mass is counted
        //LOCAL pmass IS p:DRYMASS.      // Fairings change mass. Need this as variable

        LOCAL xfeed TO True. // For parts where crossfeed can be modified.
        LOCAL thisEg TO True. // Part belongs to this eg.
        LOCAL stopWalk TO False. // Stop recursion when true.

        IF p:MASS > p:DRYMASS or p:TYPENAME = "Engine" {
            IF dbg { mLog("Found engine or tank."). }
            egtali:ADD(p).
            // Find earliest egastage and egdstage for engines.
            IF p:TYPENAME = "Engine" {
                // This should only trigger for egs with decouplers with crossfeed on. 
                LOCAL pastage TO p:STAGE. // Part becomes active
                LOCAL pdstage TO p:DECOUPLEDIN. // Part has been removed
                IF pastage > egastage { SET egastage TO pastage. }
                IF pdstage > egdstage { SET egdstage TO pdstage. }
            }
        }

        IF p:NAME = "fuelLine" {
            // Unfortunately no target information available. See kOS issue #1974
            // Workaround: Use the other side of the decoupler as the target EG.
            IF p:DECOUPLER:GETMODULE("ModuleToggleCrossfeed"):HASEVENT("disable crossfeed") {
                mLog("  !!!").
                mLog("Fuel line is attached to decoupler with crossfeed enabled!").
                mLog("DO NOT DO THAT - not supprted - ignored!").
                mLog("  !!!").
            } ELSE {
                egflli:ADD(p).
            }
        }.
        
        IF p:HASMODULE("ModuleToggleCrossfeed") {
            // Default for xfeed is True
            IF p:GETMODULE("ModuleToggleCrossfeed"):HASEVENT("enable crossfeed") {
                SET xfeed TO False.
                IF dbg { mLog("Found "+p:TITLE+" with crossfeed: "+xfeed). }
            }
        }
        
        IF p:TYPENAME = "Decoupler" {
            IF xfeed {
                // One engine group, just traverse through it
                IF dbg { mLog("Traversing through decoupler. Adding fuel to stage: "+egastage). }
            } ELSE {
                // First figure out if we come from parent or child of the decoupler.
                LOCAL pa TO p:PARENT.
                LOCAL ch TO p:CHILDREN[0].
                LOCAL procfrom TO ch. // Current eg coming from child side of decoupler
                IF egli:CONTAINS(pa) {
                    // Current eg coming from parent side of decoupler
                    SET procfrom TO pa.
                }
                // Keep decouplers on the side with the lower stage number (later). This is
                // only done to have another way to find which engine group another group is
                // connected to. (An earlier stage can look for engine:SEPARATOR in all
                // engine groups to find out which eg is next.)
                IF procfrom:DECOUPLEDIN < p:STAGE {
                    // Found decoupler to earlier stage
                    // Count for this engine group
                    procli:ADD(p:UID).
                    egli:ADD(p).
                    IF dbg { mLog("Keep in this eg!"). }
                } ELSE {
                    // Found decoupler to later stage
                    SET thisEg TO False.
                    IF dbg { mLog("Count in other eg!"). }
                    // Count for later engine group.
                }
                // Do not traverse through decoupler.
                SET stopWalk TO True.
            }
        }
        
        IF thisEg {
            procli:ADD(p:UID).
            egli:ADD(p).
            IF dbg { mLog(p:DECOUPLEDIN+","+p:STAGE+","+p:TITLE+","+p:NAME+","+p:TYPENAME+","+l). }
        }
        
        // The following parts have no Crossfeed. Stop the "walk" here.
        FOR nocf IN nocflist {
            IF p:TITLE:CONTAINS(nocf) {
                IF dbg { mLog("Found "+p:TITLE+" with crossfeed: "+False). }
                SET stopWalk TO True.
                BREAK.
            }
        }

        IF stopWalk { RETURN True. }
        
        LOCAL children TO p:CHILDREN.
        FOR child IN children {
            eTree(child,l+1).
        }
        IF p:HASPARENT {
            eTree(p:PARENT,l-1).
        }

        RETURN True.
    }
    
    FUNCTION egLog {
        // Loop over engine groups - for printing con, thruV and fma
        IF dbg {
            mLog(" ").
            mLog("Eg info").
            FROM {local i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
                // For printing
                mLog("Eg: "+i+" egastage: "+eg[i]:egastage).
                mLog("s,con                            ,thruV                              "
                     +",fma                                ,flt").
                FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
                    LOCAL scon TO "".
                    LOCAL sthruV TO "".
                    LOCAL sfma TO "".
                    LOCAL sflt TO "".
                    LOCAL x TO 0.
                    UNTIL x >= fuli:LENGTH {
                        SET scon TO scon+","+nuform(con[i][s][x],3,3).
                        SET sthruV TO sthruV+","+nuform(thruV[i][s][x],4,2).
                        SET sfma TO sfma+","+nuform(fma[i][s][x],4,2).
                        SET sflt TO sflt+","+nuform(flt[i][s][x],4,2).
                        SET x to x + 1.
                    }
                    mLog(s+scon+sthruV+sfma+sflt).
                }
            }
        }
    }
}
