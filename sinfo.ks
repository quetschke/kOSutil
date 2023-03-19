// sinfo.ks - Collect stage stats. Walk the tree starting from an engine recursively
// Copyright © 2021, 2022, 2023 V. Quetschke
// Version 0.9.5, 03/19/2023
@LAZYGLOBAL OFF.

// Enabling dbg will create a logfile (0:sinfo.log) that can be used for
// improving and debugging the script.
//LOCAL dbg TO TRUE.
LOCAL dbg TO FALSE.

// TODO: SRBs share fuel in eg, but not in "reality". Average consuption and fuelmass for SRBs will fail for
//       "unmatched" SRBs. Possible solution: Create an eg for every SRB. Maybe later ...

// See https://github.com/quetschke/kOSutil/blob/main/sinfo.md for additional information.

RUNONCEPATH("libcommon").

// Collect stage stats

// stinfo([atmo]) description
// stinfo takes the following (optional) parameter:
//   atmo:  Determines atmostpheric pressure to be used.
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

// General structure of the sinfo function
//
// The calculation of Delta V requires the knowledge of fuel consumption and thrust (this implies ISP and
// mass). The overall structure is set up to find this and related information for every stage (or substage)
// for the vessel.
//
// The function determines the available fuel per engine, or engine group (more about this below.)
// Stage numbering:
// x Stages are counted from the current stage (STAGE:NUMBER) to 0. A value -1 is
//   possible and means never decoupled or never activated.
// x part:DECOUPLEDIN The part is considered part of the vessel until this value is
//   reached. We use
//     lst = part:DECOUPLEDIN-1 (last stage)
//   to track the stage when the part is still counted for the mass.
// x part:STAGE The part gets staged/activated. ast = part:STAGE.
//
// In the end the function tries to provide stage informaton listing like KER/MJ, with:
// "start mass, end mass, staged/dropped mass, burned fuel, TWR s/e, thrust, ISPg0, DV, duration"
//
// Some variables use futype as an array. With
//   enum fuli = {0=LiquidFuel, 1=Oxidizer, 2=SolidFuel, 3=XenonGas}
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
// 1. First the script loops over all engines and fuel ducts to create engine groups (eg). An eg is
//    made up by all parts attached to the same fuel reservoir (connected tanks).
//    Each eg keeps the information in the form eg[idx]:key:
//      egli     List of parts in eg
//      egtali   Holds all tanks and engines from engine group.
//      egfdli   Holds all fuel duct parts from engine group. (Currently only one fuel duct per engine
//               group is supported.)
//      egfddest Holds the destination eg for the fuel duct parts from engine group.
//      egfdsrc  Holds the fd source egs for the engine group.
//      egastage Stage when eg becomes active
//      egdstage Stage when eg is completely decoupled. Engine groups might span multiple staging events.
//    The following variables are used to store stage dependent information. (They are initialized in
//    point 3. below.:
//      con[eg][st][fu]   Fuel consuption in eg, by stage and fuel
//      thruV[eg][st][fu]  Thrust in eg, by stage and fuel
//      thruA[eg][st][fu]  Thrust in eg, by stage and fuel
//    As each eg is actually subdivided in fu groups by fuel, we sometime use fuel engine group (fueg) to
//    describe the possible fuel dependent engine groups that use different fuels and can have different
//    burn durations within one engine group.
//    Note:
//    We use some trickery to distinguish Rocket Engines for nuclear fuel engines. Rocket engines
//    use 9u LF per 11u OX. NERV engines use only LF. Both have a density of 0.005t/u.
//    Store rocket engines fuel only under OX and NERV fuel under LF.
//
// 2. Loop over all parts
//    x Check for parts not connected to an eg.
//    x Add all drymass (non consumables) to the last stage where mass is
//      counted (p:DECOUPLEDIN+1).
//    x Correct for fairing panel mass
//    x Add fuel from tanks not in engine groups to stage mass. Also add fuel that is not used by
//      the supported engines (fuli[]).
//
// 3. Loop over engine groups
//    x Initialize variables.
//    x Check for fuel ducts and find targets.
//
//    The plan is to create a list of all eg that deliver fuel to an eg.
//    Then calculate the burn times for the source and target egs.
//    Global variables added in this loop:
//      fdtotal     Number of active fuel ducts.
//      actfdstart     List of eg that have a fd without being fed by one.
//      actfdend       List of eg that are being fed by a fd without having one going out.
//
// 3a. Loop to show FD debug output
//
// 4. Loop over engine groups to collect consumption, thrust and fuel mass information.
//    Set fd-downstream consumption, thrust and fuel info per eg, fu:
//      conW[eg][fu]    Fuel consuption in eg, by stage and fuel
//      thruVW[eg][fu]  Thrust in eg, by fuel
//      thruAW[eg][fu]  Thrust in eg, by fuel
//      cfma[eg][fu]    Fuel mass in eg, fu. Gets updated during substage calculation.
//
// 5. Loop over stages and create substage information.
//    Delta V calculation depends on fuel consumption and thrust (this implies ISP and mass), but when
//    different fuel engine groups burn for different lengths of time during a stage one needs to break
//    the stage into substages, each with different consuption and thrust information that is accumulated
//    from the eg at the various times during the stage.
//    Starting with the shortest burns assures that all active engines are burned at the beginning and later
//    burns have less and less engines (consumption/thrust) participating.
//    The information is stored in sub[s][i]:XX with XX = bt, con, thruV and thruA
//     bt ..  Burn duration of current substage.
//     con .. Total fuel consumption of the active fueg.
//     thruV .. Total vac thrust of the active fueg.
//     thruA .. Total thrust of the active fueg at atmospheric pressure.
//
// 6. Finally calculate mass, ISP, dV, thrust, TWR, burntime, etc.
//
// Problems and additional considerations
// 1. Fuel ducts need kOS tags to to mark the target of the duct. Assigning the same tag to the fuel duct
//    and the target it attaches iss needed to recognize the connection. This is needed because kOS does
//    not provide the target information of the part that a fuel duct connects to.
//    See https://github.com/quetschke/kOSutil/blob/main/sinfo.md#requirements-and-usage
// 2. Decoupling parts (decoupler, separator, engine plate, structural pylon, small hardpoint and docking
//    ports) with staging enabled provide no information to kOS about which side they stay attached to
//    when staged, and where their mass needs to be counted.
//    Technical: Independently of the orientation of the decoupler or engine plate p:DECOUPLER has the same
//    value as the next part towards the root part. (This also happens to be the parent node).
//    Implementation: The script assumes a normal/standard orientation for those parts, meaning the
//    decouplers stay with the earlier stage and are removed after staging. Engine plates are an exception
//    and are assumed to stay attached with the later stage after staging.
//    Option: As this default setting might not reflect the orientation of the part a kOS tag on the
//    decoupler can be used to indicate the part is rotated:
//    - kOS tag "reverse" tells the script the decoupling part is reversed/upside down.
//  2.a Engine plates are even more problematic because they are decouplers with "attach nodes" where parts
//    are supposed to remain attached. When staging/decoupling is enabled the script does not know which
//    parts remain attached and what is the decoupled node.
//    Technical: With "staging enabled" all children have the same DECOUPLEDIN, STAGE and DECOUPLER
//    information as if they were decoupled.  The DECOUPLEDIN information is correct when the part is
//    connected to the node that actually decouples, or is one of its depedents. The parts connected
//    to the "attach nodes" or as surface attachments (and their dependents) have the wrong information.
//    The STAGE info seems correct for all dependents that are staged parts (engines).
//    This leaves no way to identify the decoupled node (the order of the children depends on the order they
//    were attached, not the node).
//    Implementation: The script uses the following approach for parts that have p:DECOUPLER pointing to an
//    engine plate. (The engine plate:DECOUPLER = top node:DECOUPLER (parent)):
//    - If engine plate:DECOUPLER = dependent:DECOUPLER the dependents values are correct. (Always the
//      parent node)
//    - If the part has a kOS tag starting with "epa" assume the part remains attached and is not decoupled.
//      Use the DECOUPLEDIN indormation from the engine plate part.
//    - If the part has a kOS tag starting with "epd" assume the part is not decoupled.
//      Keep the DECOUPLEDIN information from the part.
//    - If the part is an engine that is directly attached to the engine plate assume it remains attached
//      and is not decoupled.
//    - In all other cases assume the part is decoupled.
//    This approach allows to use engine plates in most cases to be used without using the epa and epd kOS
//    tags. On the decoupler node is rarely an engine attached directly, usually there is a tank and other
//    parts between the decoupler node and the engine. On the other hand engines are usually attached
//    directly to the engine plate when they are supposed to stay and be used after decoupling the lower part.
//    The third condition above avoides that "epa" tags need to be placed.
//    In other cases tags need to be used.
//    Examples:
//    - The engines are attached via structural or intermediate parts to the engine plate. Use the "epa" tag
//      for those parts and the engines.
//    - The engine plate is used as a cargo bay or fairing. Use the "epa" tag for the parts that will
//      remain attached.
//    - SRBs (or Twin-Boar) are examples of engines that bring their own fuel. If those are attached directly
//      to the decoupling node the "epd" tag is needed to have these parts treated correctly.
//    - The engine plate is mounted upside-down: Assign the kOS tag "reverse" to the engine plate and
//      "epd" tags to engines on attach nodes.

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

    LOCAL sub TO LIST(). // Substage info
    // Initialize a list of zeroes.
    LOCAL stZ TO LIST().
    FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
        stZ:ADD(0).
        sub:ADD(LIST()).
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

    LOCAL procli TO LIST().  // Holds all processed parts.
    LOCAL egli TO LIST().    // Holds all engine group parts.
    LOCAL egtali TO LIST().  // Holds all tanks and engines from engine group.
    LOCAL egfdli TO LIST().  // Holds all fuel line parts from engine group.
    LOCAL egastage TO 999.   // Use this as the stage the current engine group becomes active
    LOCAL egdstage TO 999.   // The stage when current engine group has been removed

    LOCAL fdtotal TO 0.      // Numer of all active fuel ducts across all eg.
    LOCAL actfdstart TO LIST(). // List of eg that have no incoming fd.
    LOCAL actfdend TO LIST().   // List of eg that have no outgoing fd.

    // Since kOS 1.4.0 TYPENAME changed from "decoupler" to "separator" for some (or all) decouplers.
    LOCAL dectyp TO LIST("decoupler", "separator").

    // Fairings with panel mass - expand later for non-stock parts
    LOCAL fairingmass TO LEXICON(
        "fairingSize1", 0.075,  // AE-FF1
        "fairingSize1p5", 0.15, // AE-FF1.5
        "fairingSize2", 0.175,  // AE-FF2
        "fairingSize3", 0.475,  // AE-FF3
        "fairingSize4", 0.8     // AE-FF4
        ).
    // Parts that "block" crossfeed across them:
    //LOCAL nocflist TO LIST("I-Beam", "Strut Connector", "Structural Panel").
    // List of parts with "fuelCrossFeed = False". Extracted from *.cfg files.
    LOCAL nocflist TO LIST("smallHardpoint",    // Squad stock
                           "structuralIBeam1", "structuralIBeam2", "structuralIBeam3",
                           "structuralPylon",
                           "structuralPanel1", "structuralPanel2",
                           "InflatableHeatShield",
                           "HeatShield0", "HeatShield1", "HeatShield2", "HeatShield3",
                           "noseCone", "rocketNoseCone", "rocketNoseCone_v2", "rocketNoseConeSize3",
                           "strutConnector",
                           "Panel0", "Panel1", "Panel1p5", "Panel2",    // Squad expansion
                           "EquiTriangle0", "EquiTriangle1", "EquiTriangle1p5", "EquiTriangle2",
                           "Size_1_5_Cone", "rocketNoseConeSize4",
                           "Triangle0", "Triangle1", "Triangle1p5", "Triangle2",
                           "HeatShield1p5" ).

    // The list of fuels known to this script. Might grow for newer versions or mods
    LOCAL fuli TO LIST("LiquidFuel", "Oxidizer", "SolidFuel", "XenonGas").
    // We use the variables to identify LF and OX.
    LOCAL LFidx TO fuli:FIND("LiquidFuel").
    LOCAL OXidx TO fuli:FIND("Oxidizer").
    LOCAL SOidx TO fuli:FIND("SolidFuel").
    LOCAL XEidx TO fuli:FIND("XenonGas").
    LOCAL fuCorr TO LIST(1, 1, 1, 1).
    // Used to correct stmass[] for LF in REs.
    SET fuCorr[OXidx] TO 20/11.
    LOCAL fuliZ TO LIST(0,0,0,0). // Placeholder for fuel types
    LOCAL fuMin TO 1e-6.    // The amount of fuel that counts as zero

    // Will be initialized after eg loop to:
    LOCAL con TO LIST().   // con[eg][st][fu]   Fuel consuption in eg, by stage and fuel
    LOCAL thruV TO LIST(). // thruV[eg][st][fu] Vac thrust in eg, by stage and fuel
    LOCAL thruA TO LIST(). // thruA[eg][st][fu] Atmospheric thrust in eg, by stage and fuel
    // 2-D lists
    LOCAL conW TO LIST().   // con[eg][fu]   FD Fuel consuption in eg, by fuel
    LOCAL conP TO LIST().   // con[eg][fu]   Possible FD Fuel consuption if fuel is available. Used to find if
                            // fuel is holding back staging.
    LOCAL thruVW TO LIST(). // thruV[eg][fu] FD Vac thrust in eg, by fuel
    LOCAL thruAW TO LIST(). // thruA[eg][fu] FD Atmospheric thrust in eg, by fuel
    LOCAL cfma TO LIST().   // cfma[eg][fu]   Fuel mass in eg, fu. Gets updated during substage calculation.
    LOCAL fdfma TO LIST().  // fdfma[eg][fu]   Cumulative fuel mass in eg, fuel.
    LOCAL fdnum TO LIST().  // Active number of fd sources that have fuel coming in (fdfma > 0).
    LOCAL burnsrc TO LIST(). // When burn > 0 which eg does the fuel come from.
    LOCAL burnsrcLF TO LIST(). // When burn > 0 which eg does the fuel come from.
    LOCAL burndu TO LIST(). // Burn duration per eg, fu.
    LOCAL donebu TO LIST(). // Has done/scheduled a burn per eg, fu.

    // 1. First the script loops over all engines and fuel ducts to create engine groups (eg).
    LOCAL elist TO -999. LIST ENGINES IN elist.
    // Find fuel ducts and add them to elist. We want to have eg without engines to handle "drop tanks" when
    // using fuel ducts.
    {   LOCAL fdlist TO SHIP:PARTSNAMED("fuelLine").
        FOR p IN fdlist {
            elist:ADD(p). // Really? kOS doesn't have a command for that?
        }
    }

    IF dbg {
        mLog("Loop over all engines and find members of engine groups").
        mLog("Ep_Decoupledin(p),p:STAGE,p:TITLE,p:NAME,p:TYPENAME,lvl").
    }
    LOCAL egidx TO 0.
    LOCAL eg TO LIST().
    FOR e IN elist {
        // To process fuel flow correctly start with the engines with the earliest decoupling

        SET egastage TO e:STAGE. // Use this as the stage the current engine group becomes active
        SET egdstage TO Ep_Decoupledin(e). // The stage when current engine group has been completely removed

        SET egli TO LIST(). // Collect engine group list
        SET egtali TO LIST(). // Holds all tanks and engines from engine group.
        SET egfdli TO LIST(). // Holds all fuel line parts from engine group.

        IF dbg { mLog("egdstage: "+egdstage+" / egastage: "+egastage). }
        IF eTree(e,0) { // Find the engine group where this engine belongs to.
            // collects values in egli, egtali, egfdli, egastage, egdstage.
            // Successfully returned
            IF dbg { mLog("Found eg: "+egidx). }
            eg:ADD(0).
            SET eg[egidx] TO LEXICON().
            SET eg[egidx]["egli"] TO egli.
            SET eg[egidx]["egtali"] TO egtali.
            SET eg[egidx]["egfdli"] TO egfdli.
            SET eg[egidx]["egastage"] TO egastage.
            SET eg[egidx]["egdstage"] TO egdstage.

            SET eg[egidx]["egfddest"] TO LIST(). // Holds all fuel duct eg destinations from engine group.
            SET eg[egidx]["egfdsrc"] TO LIST(). // Holds the fd source egs for the engine group.
            SET eg[egidx]["actfddest"] TO LIST(). // Holds all active fuel duct eg destinations from engine group.
            SET eg[egidx]["actfdsrc"] TO LIST(). // Holds the active fd source egs for the engine group.

            SET egidx TO egidx+1.
        }
        // If False, this engine is already part of another eg.
        IF dbg { mLog(" "). }
    }

    // 2. Now loop over all parts
    LOCAL plist TO -999. LIST PARTS IN plist.
    IF dbg {
        mLog("Loop over all parts").
        mLog("kst,Ep_Decoupledin(p),p:STAGE,p:TITLE,p:TYPENAME,p:MASS,p:DRYMASS,fuel,ineg").
    }
    FOR p IN plist {
        LOCAL ineg TO 1.
        IF NOT procli:CONTAINS(p:UID) {
            // List the ones we missed.
            SET ineg TO 0.
        }
        LOCAL lst is Ep_Decoupledin(p)+1.  // Last stage where mass is counted

        LOCAL ast is p:STAGE.  // Stage where part is activated
        LOCAL kst is lst.  // Stage number like in KER/MJ

        LOCAL pmass IS p:DRYMASS. // Fairings change mass. Need this as variable

        IF p:TYPENAME = "LaunchClamp" { SET pmass TO 0. } // Ignore mass of clamps.

        // 1 = mass normally stays with decoupled (earlier) stage, -1 = mass stays with the next stage.
        LOCAL is_decoup TO 0.
        IF dectyp:CONTAINS(p:TYPENAME) {
            // Decouplers and separators have only mass prior to being activated,
            // they stay on without mass.
            IF p:NAME:STARTSWITH("Decoupler")
               OR p:NAME:STARTSWITH("radialDe") OR p:NAME:STARTSWITH("smallHard")
               OR p:NAME:STARTSWITH("structuralPyl") OR p:NAME:STARTSWITH("HeatShield") {
                // Warning! The script assumes that lower/later stages loose the mass. It cannot detect if
                // a decoupler is mounted upside down. Use kOS tag "reverse" to guide the script.
                SET is_decoup TO 1.
            } ELSE IF p:NAME:STARTSWITH("Separator") {
                // Separators always loose their mass upon decoupling
                SET is_decoup TO 2.
            } ELSE IF p:NAME:STARTSWITH("EnginePlate") {
                // Engine plates keep their mass, unless reversed.
                SET is_decoup TO -1.
            } ELSE {
                // Found unknown decoupler
                mLog("Unknown decoupler: "+p:TYPENAME+" / "+p:TITLE+" / "+p:NAME).
                PRINT 1/0.
            }
        }

        IF p:TYPENAME = "DockingPort" AND p:HASMODULE("ModuleDockingNode") {
            // Docking ports used as decouplers have the mass where the port is attached to.
            // kOS cannot detect automatically which side a docking port is attached to.
            IF p:GETMODULE("ModuleDockingNode"):HASEVENT("port: disable staging") {
                // Warning! The script assumes that lower/later stages loose the mass. It cannot detect if
                // a docking port is mounted upside down. Use kOS tag "reverse" to guide the script.
                SET is_decoup TO 1.
            }
        }

        // Decide where the mass of the decouplers stays
        IF is_decoup <> 0 {
            LOCAL is_reverse TO 0.
            IF p:GETMODULE("KOSNameTag"):GETFIELD("name tag"):STARTSWITH("reverse") {
                SET is_reverse TO 1.
                IF dbg { mLog("   - "+p:TITLE+" / reverse"). }
            } ELSE {
                IF dbg { mLog("   - "+p:TITLE+" / normal"). }
            }
            IF is_decoup = 1 {
                // Mass normally gets decoupled
                IF NOT is_reverse { SET kst TO ast+1. }
            } ELSE IF is_decoup = 2 {
                // Mass always gets decoupled
                SET kst TO ast+1.
            } ELSE {
                // Mass normally stays
                IF is_reverse { SET kst TO ast+1. }
            }
        }

        // Fairings need special treatment
        IF fairingmass:HASKEY(p:NAME) { // A fairing
            //mLog(p:TITLE+" / "+p:NAME).
            LOCAL fpanel IS p:MASS - fairingmass[p:NAME].
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
        // Log the part. Use plist.ks to generate more information.
        IF dbg {
            mLog(kst+","+Ep_Decoupledin(p)+","+p:STAGE+","+p:TITLE+","+p:TYPENAME+","
                +p:MASS+","+p:DRYMASS+","+(p:MASS-p:DRYMASS)+","+ineg).
        }
    }


    // 3. Loop over engine groups - Initialize variables and follow fuel ducts.
    IF dbg { mLog(" "). }
    FROM {LOCAL i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
        // Initialize variables 3-D lists for all eg:
        con:ADD(stZ:COPY).  // Consumption - Now con[eg][st]
        thruV:ADD(stZ:COPY). // Thrust vacuum
        thruA:ADD(stZ:COPY). // Thrust atmospheric pressure
        FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
            SET con[i][s] TO fuliZ:COPY.   // Now [eg][st][fu]
            SET thruV[i][s] TO fuliZ:COPY.  // Now [eg][st][fu]
            SET thruA[i][s] TO fuliZ:COPY.  // Now [eg][st][fu]
        }
        // Initialize 2-D lists for all eg:
        conW:ADD(fuliZ:COPY).   // Consumption - Now con[eg][st]
        conP:ADD(fuliZ:COPY).   // Consumption - Now con[eg][st]
        thruVW:ADD(fuliZ:COPY). // Thrust vacuum
        thruAW:ADD(fuliZ:COPY). // Thrust atmospheric pressure
        cfma:ADD(fuliZ:COPY).    // Fuel mass
        fdfma:ADD(fuliZ:COPY).   // Cumulative fuel mass in eg, fuel.
        fdnum:ADD(fuliZ:COPY).  // Active number of fd sources that have fuel coming in (fdfma > 0).
        burnsrc:ADD(fuliZ:COPY).  // When burn > 0 which eg does the fuel come from.
        burnsrcLF:ADD(fuliZ:COPY).  // When burn > 0 which eg does the fuel come from.
        burndu:ADD(fuliZ:COPY).  // Burn duration per eg, fu.
        donebu:ADD(fuliZ:COPY).  // Has done/scheduled a burn per eg, fu.
        // Check where fuel ducts go.
        IF eg[i]:egfdli:LENGTH > 1 {
            PRINT " ".
            PRINT "The sinfo library supports only one fuel duct going out of a engine group!".
            PRINT " ".
            PRINT 1/0.
        }
        // This loop is either executed once, or not at all.
        FOR fl IN eg[i]:egfdli {
            IF dbg {mLog("Fuel duct in eg: "+i). }
            LOCAL fulinetarget TO False.
            // Every part has a tag
            LOCAL kTag TO fl:GETMODULE("KOSNameTag"):GETFIELD("name tag").
            // Or kTag = fl:TAG ???
            IF kTag = "" {
                SET kTag TO "<none>".
            } ELSE {
                IF kTag = "<none>" {
                    PRINT "Fuel Ducts cannot have a kOS tag with the value <none>.".
                    PRINT "That tag value is used for internal fuel duct processing,".
                    PRINT "Please use a different tag to identify fuel duct targets.".
                    PRINT " ".
                    RETURN 0.
                }
                // Find corresponding tags
                LOCAL alltags TO SHIP:PARTSTAGGED(kTag).
                LOCAL alltags2 TO LIST().
                FOR p IN alltags {
                    IF p:NAME <> "fuelLine" {
                        alltags2:ADD(p).
                    }
                    IF dbg { mLog("Tag: "+kTag+" Part: "+p:TITLE). }
                }
                IF alltags2:LENGTH <> 1 {
                    PRINT "There needs to be exactly one target part with the same".
                    PRINT "kOS name tag as the fuel duct!".
                    PRINT "Found: "+alltags2:LENGTH+" targets with kOS tag: "+ktag.
                    PRINT "The tag will be ignored and the decoupler logic be used.".
                    PRINT " ".
                    SET kTag TO "<none>".
                } ELSE {
                    SET fulinetarget TO alltags2[0].
                }
            }
            IF kTag = "<none>" {
                // Find the eg of the other side of the decoupling decoupler.
                LOCAL pa TO fl:DECOUPLER:PARENT.
                LOCAL ch TO fl:DECOUPLER:CHILDREN[0].
                // Assume the decoupler child is in current eg.
                SET fulinetarget TO pa.
                IF eg[i]:egli:CONTAINS(pa) {
                    // No, the decoupler parent is in current eg.
                    SET fulinetarget TO ch.
                }
            }
            // Find the eg the fuel duct is pointing to.
            LOCAL fddesteg TO -1.
            FROM {LOCAL x IS 0.} UNTIL x >= eg:LENGTH STEP {SET x to x+1.} DO {
                IF eg[x]:egli:CONTAINS(fulinetarget) {
                    SET fddesteg TO x.
                    BREAK.
                }
            }
            // Now, if the decoupler has crossfeed enabled, or the kTag target is pointing to the same
            // eg, the fuel duct has no effect and can be ignored.
            IF fddesteg = i {
                mLog("ignore fuel duct!").
            } ELSE {
                eg[i]:egfddest:ADD(fddesteg). // Add to fuel duct eg destination list.
                eg[fddesteg]:egfdsrc:ADD(i).          // Add to source list
                SET fdtotal TO fdtotal + 1.
            }
            IF dbg { mLog("FD: eg "+i+" -> eg "+fddesteg+"/"+fulinetarget:TITLE+"/kOS tag: "+kTag). }
        }
    }

    // 3a. Loop over engine groups - again.
    // Create/show fd debug output.
    IF dbg {
        mLog(" ").
        LOCAL fdstart TO LIST(). // List of eg that have no incoming fd.
        LOCAL fdend TO LIST().   // List of eg that have no outgoing fd.
        FROM {LOCAL i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
            IF eg[i]:egfddest:LENGTH > 0 {
                LOCAL srcstr TO "".
                IF eg[i]:egfdsrc:LENGTH = 0 {
                    fdstart:ADD(i).
                    SET srcstr TO "- ".
                } ELSE {
                    FOR ii IN eg[i]:egfdsrc {
                        SET srcstr TO srcstr+ii+" ".
                    }
                }
                mLog("FDs in eg "+i+": src: < "+srcstr+"> to dest: <"+eg[i]:egfddest[0]+">").
            } ELSE IF eg[i]:egfdsrc:LENGTH > 0 { // No outgoing, but has incoming fd.
                IF dbg { mLog("FD end eg: "+i). }
                fdend:ADD(i).
            }
        }
        LOCAL pstr TO " ".
        FOR ii in fdstart {
            SET pstr TO pstr+ii+" ".
        }
        mLog("fd start eg: "+pstr).
        SET pstr TO " ".
        FOR ii in fdend {
            SET pstr TO pstr+ii+" ".
        }
        mLog("fd end eg: "+pstr).
    }

    // 4. Loop over engine groups - again
    // Set consumption, thrust and fuel info per eg, s, fu.
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
                // This adds to: con[i][s][f], thruV[i][s][f], thruA[i][s][f], sticon[s],
                // stithruV[s] and stithruA[s]
                setConThru(x, i).
            }
            // Part with fuel (Tank or SRB). Add the fuel to the eg.
            IF x:MASS > x:DRYMASS {
                FOR r IN x:RESOURCES {
                    LOCAL fti TO fuli:FIND(r:NAME).
                    IF fti >= 0 {
                        // Fuel in eg without stage dependency
                        SET cfma[i][fti] TO cfma[i][fti] + r:AMOUNT*r:DENSITY.
                    } // Fuel not in fuli has been added to stmass[] already.
                }
            }
        }
    }
    // Log con, thru, ... info.
    egLog().

    // 5. Loop over stages and create substage information.
    // The information is stored in sub[s][i]:XX with XX = bt, con, thruV and thruA
    // Every substage enters: LEXICON("bt", 0, "con", 0, "thruV", 0, "thruA", 0)).
    FROM {LOCAL s IS STAGE:NUMBER.} UNTIL s < 0 STEP {SET s TO s-1.} DO {
        IF dbg {
            mLog(" ").
            mLog("s: "+s+"/"+STAGE:NUMBER+" New stage.").
        }
        LOCAL btstage TO 0. // Cumulative burn time for current stage.

        // Initialize FD info
        SET conW TO LIST(). // Is this needed?
        SET conP TO LIST(). // Is this needed?
        SET actfdstart TO LIST().
        SET actfdend TO LIST().
        FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
            // Initialize 2-D lists for all eg:
            conW:ADD(fuliZ:COPY).   // Is this needed?
            conP:ADD(fuliZ:COPY).   // Is this needed?

            SET eg[e]:actfdsrc TO LIST().
            SET eg[e]:actfddest TO LIST().
            // The eg don't need to be active (egastage) to be added.
            IF s > eg[e]:egdstage {
                FOR ee IN eg[e]:egfdsrc {
                    IF s > eg[ee]:egdstage {
                        eg[e]:actfdsrc:ADD(ee).
                    }
                }
                FOR ee IN eg[e]:egfddest {
                    IF s > eg[ee]:egdstage {
                        eg[e]:actfddest:ADD(ee).
                    }
                }
                IF eg[e]:actfddest:LENGTH = 0 { // No outgoing fd.
                    IF eg[e]:actfdsrc:LENGTH > 0 {
                        // Has incoming fd
                        //mLog("actFD end eg: "+e).
                        actfdend:ADD(e).
                    } ELSE IF s <= eg[e]:egastage AND s > eg[e]:egdstage {
                        // No incoming and no outgoing FD. Add to actfdend and actfdstart if stage is on.
                        //mLog("actFD end eg: "+e).
                        actfdend:ADD(e).
                        //mLog("actFD start eg: "+e).
                        actfdstart:ADD(e).
                    }
                }
                // No incoming, but outgoing FD
                IF eg[e]:actfdsrc:LENGTH = 0 AND eg[e]:actfddest:LENGTH > 0 {
                    //mLog("actFD start eg: "+e).
                    actfdstart:ADD(e).
                }
                // The case for no incoming and no outgoing FD is handled above.
            }
        }

        IF dbg {
            LOCAL sstr TO "actfdstart:".
            FOR i IN actfdstart { SET sstr TO sstr +" "+i. }
            mLog(sstr).
            SET sstr TO "actfdend:  ".
            FOR i IN actfdend { SET sstr TO sstr +" "+i. }
            mLog(sstr).
        }

        // Preparations - This is repeated inside the UNTIL loop.
        FOR i IN actfdend {
            // Set fdfma[e][f] as the cumulative fuel coming into an eg.
            // Needed for setConThruFD().
            setFDfma(i).
            // Set fd con and thru.
            setConThruFD(i,s).
        }
        IF dbg { mLog("Before UNTIL loop:"). }
        egCoFuLog(s).


        LOCAL dsloop TO 0.

        // Check if we can stage - repeat at end of UNTIL loop
        LOCAL dostage TO False.
        LOCAL hasdropeg TO False.
        LOCAL nofuel TO True.
        LOCAL fuleft TO 0. // Fuel left that cannot be burned.
        LOCAL acteg TO 0.
        LOCAL dropeg TO "".
        FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
            // Assume we can stage
            IF s <= eg[e]:egastage { SET acteg TO acteg+1. }
            IF s = eg[e]:egdstage+1 {
                // Make sure there are stages to drop, e.g. with s = eg[e]:egdstage+1.
                SET hasdropeg TO True.
                SET dropeg TO dropeg+" "+e.
                // Unless there is fuel left in a stage we can stage.
                LOCAL tfuel TO 0.
                // Check for fuel and consumption
                FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                    IF conP[e][f] > 0 {
                        SET tfuel TO tfuel + cfma[e][f].
                        // For RE LF & OX prohibit staging
                        IF f = OXidx { SET tfuel TO tfuel + cfma[e][LFidx]. }
                    }
                    // Collect all fuel left.
                    SET fuleft TO fuleft + cfma[e][f].

                }
                IF tfuel > 1e-7 {
                    SET nofuel TO False.
                    //IF dbg { mLog("Cannot stage yet"). }
                }
            }
        }
        // We need to stage if no eg is active.
        IF acteg < 1 {
            SET dostage TO True.
            IF dbg { mLog("s: "+s+" No stages active - stage!"). }
        } ELSE IF nofuel AND hasdropeg {
            SET dostage TO True.
            SET stleft[s] TO fuleft.
            IF dbg { mLog("s: "+s+" All stages empty - stage: "+dropeg+" dropping fuel: "+ROUND(stleft[s],3)). }
        }
        IF dbg AND dostage { mLog("We can stage / skip UNTIL loop."). }

        // Loop inside stage to determine burn intervals.
        UNTIL dostage = True {
            SET dsloop TO dsloop + 1.
            IF dbg {
                mLog(" ").
                mLog("s: "+s+" UNTIL loop: "+dsloop).
                egFuLog(s).
            }

            // Initialize some variables.
            FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
                // Initialize back to zero:
                SET burndu[e] TO fuliZ:COPY.  // Set durations back to zero.
                SET donebu[e] TO fuliZ:COPY.  // Set done/scheduled back to zero.
            }

            IF dbg {
                LOCAL sstr TO "actfdstart:".
                FOR i IN actfdstart { SET sstr TO sstr +" "+i. }
                mLog(sstr).
                SET sstr TO "actfdend:  ".
                FOR i IN actfdend { SET sstr TO sstr +" "+i. }
                mLog(sstr).
                mLog(" ").
            }

            // Loop over actfdstart and find burn durations.
            LOCAL minburn TO 1e12. // One terasecond
            FOR e IN actfdstart { // There can be more than one entry.
                //mLog("actfdstart e:"+e+" conW_OX: "+conW[e][OXidx]).
                // calculate burn durations.

                LOCAL bustr TO "".
                LOCAL bsrcstr TO "".
                FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                    // Note: burn for LF is wrong when RE is present. Fixed below.
                    LOCAL burnV TO CHOOSE 0 IF conW[e][f] = 0 ELSE cfma[e][f] / conW[e][f].
                    // Make sure REs have all fuel.
                    IF f = OXidx {
                        // Make sure we have LF
                        LOCAL burnLF TO CHOOSE 0 IF conW[e][f] = 0 ELSE cfma[e][LFidx] / (conW[e][f]*ox2lf).
                        SET burnV TO MIN(burnV,burnLF).
                        SET burnsrcLF[e][OXidx] TO e.
                        SET burnsrcLF[e][LFidx] TO e.
                    }
                    SET burndu[e][f] TO burnV.
                    SET burnsrc[e][f] TO e.
                    LOCAL edstr TO "".
                    // Find alternative fuel
                    // Loop over all and keep/reset the lowest fuel duct level (fdl) (all fdl=0).
                    LOCAL ee TO e.
                    IF burnV < 0.01 { // Shorter than a physics tick
                        LOCAL stoploop TO False.
                        LOCAL ed TO -1.
                        UNTIL stoploop = True {
                            IF eg[ee]:actfddest:LENGTH > 0 {
                                SET ed TO eg[ee]:actfddest[0].
                                SET edstr TO edstr+"->"+ed.
                                IF fdnum[ed][f] > 0 {
                                    // Our current fd path doesn't have fuel, but other paths into ed have
                                    // fuel. Do not pursue this path.
                                    IF dbg {
                                        mLog("  FD path with fuel exists - ignore "+e+edstr+" for f: "+f).
                                    }
                                    SET burnsrc[e][f] TO -1. // Not used.
                                    BREAK.
                                }
                                IF donebu[ed][f] {
                                    // If there is more than 1 fd path to this eg and all have used up their
                                    // fuel, but are not staged this condition can trigger.
                                    // We ignore it if it has been reached before.
                                    IF dbg {
                                        mLog("  Has been reached by other path - ignore "+e+edstr+" for f: "+f).
                                    }
                                    SET burnsrc[e][f] TO -1. // Done already.
                                    BREAK.
                                }
                                // Can we burn fuel in this stage?
                                IF conW[ed][f] > 0 {
                                    // At this point we have to distinguish if we can only burn the fuel in
                                    // this stage, or if FD are feeding it. This can only happen for RE.
                                    IF f = OXidx {
                                        IF  fdfma[ed][f] > 0 AND fdfma[ed][LFidx] > 0 {
                                            // If we are here this stage can burn RE
                                            // We assume the tank the farthest away gets drained first.
                                            // See google doc - not necessarily always true.
                                            // If multiple tanks are there on the same level we burn them
                                            // sequentially. In this case it is equivalent as the consumption
                                            // normally would be split between the tanks, but in this case the
                                            // full consumption is used on one tank after the other. The burn
                                            // duration is the same, and the mass flow also.
                                            LOCAL LFsrc TO ed.
                                            LOCAL OXsrc TO ed.
                                            // IF fdfma > cfma it means we have individual (not both LF and
                                            // OX) pockets of fuel. In that case we need to find those
                                            // recursively.
                                            IF fdfma[ed][f] > cfma[ed][f] OR fdfma[ed][LFidx] > cfma[ed][LFidx] {
                                                IF dbg {
                                                    mLog("Found LF or OX in earlier engine group. Find sources for eg "+e+" -> "+ed).
                                                }
                                                LOCAL rval TO getREsrc(ed). // Find the fuel the farthest away.
                                                SET LFsrc TO rval[0].
                                                SET OXsrc TO rval[1].
                                            } // Otherwise we use the local fuel.
                                            LOCAL burnOX TO cfma[OXsrc][OXidx] / conW[ed][OXidx].
                                            LOCAL burnLF TO cfma[LFsrc][LFidx] / (conW[ed][OXidx]*ox2lf).
                                            IF dbg {
                                                mLog("   LF/OX src-eg: "+LFsrc+"/"+OXsrc+" fuel: "
                                                +ROUND(cfma[LFsrc][LFidx],3)+"/"+ROUND(cfma[OXsrc][OXidx],3)
                                                +" burn: "+ROUND(burnLF,2)+"/"+ROUND(burnOX,2)).
                                            }

                                            SET stoploop TO True.
                                            SET burndu[e][f] TO MIN(burnOX,burnLF).
                                            SET burnsrc[e][f] TO ed.
                                            SET burnsrcLF[e][OXidx] TO OXsrc.
                                            SET burnsrcLF[e][LFidx] TO LFsrc.
                                            SET donebu[ed][f] TO 1.

                                            IF burndu[e][f] = 0 {
                                                mLog("Investigate!").
                                                PRINT 1/0.
                                            }
                                        }
                                    } ELSE {
                                        // Only local fuel
                                        SET burnV TO CHOOSE 0 IF conW[ed][f] = 0 ELSE cfma[ed][f] / conW[ed][f].
                                        IF burnV > 0 {
                                            SET stoploop TO True.
                                            SET burndu[e][f] TO burnV.
                                            SET burnsrc[e][f] TO ed.
                                            // The next two are only needed for OXidx
                                            SET burnsrcLF[e][OXidx] TO -1.
                                            SET burnsrcLF[e][LFidx] TO -1.
                                            SET donebu[ed][f] TO 1.
                                        }
                                    }
                                }
                                SET ee TO ed.
                            } ELSE {
                                // Nothing to follow - stop now.
                                SET stoploop TO True.
                                SET burnsrc[e][f] TO -1. // Found no fuel.
                            }
                        }
                    } ELSE {
                        // Mark this eg had a burn.
                        SET donebu[e][f] TO 1.
                    }
                    IF burnV > 0 AND dbg {
                        mLog(" Burn: "+ROUND(burnV,4)+" for "+e+edstr+" for f: "+f).
                    }
                    IF dbg {
                        SET bustr TO bustr+","+nuform(burndu[e][f],4,1).
                        SET bsrcstr TO bsrcstr+","+nuform(burnsrc[e][f],2,0).
                    }
                }
                IF dbg { mLog("eg,"+e+",bt"+bustr+",src"+bsrcstr). }

                // Correct for RE vs. NERV fuel and oxidizer usage
                // This works for engine groups without fuel ducts. Can I break it with fuel ducts?
                // Testcases "SI kOS test III-nerv fl" and "SI kOS test IIIa-nerv fl" work.
                IF conW[e][LFidx] > 0 AND conW[e][OXidx] > 0 { // Only when RE and NERV are active.
                    LOCAL LFXcon TO conW[e][LFidx] + conW[e][OXidx]*ox2lf.
                    // Combined NERV and RE LF based burn.
                    LOCAL LFXburn TO CHOOSE 0 IF LFXcon = 0 ELSE cfma[e][LFidx]/LFXcon.
                    LOCAL OXburn TO burndu[e][OXidx]. // Recalulated below
                    LOCAL LFburn TO burndu[e][LFidx]. // Recalulated below - certainly wrong when RE present
                    IF dbg { mLog("  NERV+RE LF burn: "+ROUND(LFXburn,1)
                            +" Corrected:"). }
                    IF LFXburn < OXburn {
                        // Shorten OXburn
                        SET OXburn TO LFXburn. // Less LF than OX for RE (OX leftover)
                        SET burndu[e][OXidx] TO OXburn.
                    }
                    // No need to treat the case of OXburn < LFXburn. The Nerv burn is recalculated based
                    // on the OXburn anyway.
                    // If a NERV is present, no leftover. Otherwise this case covers for RE with less
                    // OX than LF. This leads to LF leftover and a LFburn of 0s.
                    // Recalculate LFburn, with RE in mind
                    SET LFburn TO CHOOSE 0 IF conW[e][LFidx] = 0 ELSE
                        (cfma[e][LFidx] - OXburn*conW[e][OXidx]*ox2lf) / conW[e][LFidx]. // No leftover
                    SET burndu[e][LFidx] TO LFburn.
                    IF dbg {
                        SET bustr TO "".
                        FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                            SET bustr TO bustr+","+nuform(burndu[e][f],4,1).
                        }
                        mLog("eg,"+e+",bt"+bustr).
                    }
                }
            }

            FOR e IN actfdstart {
                // Find minimum value
                FROM {local f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                    IF burndu[e][f] > 0 AND burndu[e][f] < minburn { SET minburn TO burndu[e][f]. }
                }
            }

            // SRBs don't follow fuel lines.
            // Note: Another issue is that SRBs don't share fuel in eg. This will fail if different
            // consumption and/or fuelmass SRBs are joined in one eg.
            FROM {local e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
                // SRBs can be firing in all active eg. As we don't follow fd, like for all other engine
                // types, just check SRBs in all eg that are not in actfdstart. Check first for SRB fuel
                // to shortcut the conditions as fast as possible.
                IF cfma[e][SOidx] > 0 AND NOT(actfdstart:CONTAINS(e)) AND s <= eg[e]:egastage
                   AND s > eg[e]:egdstage AND  conW[e][SOidx] > 0 {
                    // Check for conW[e][SOidx] as an engine can be inactive even when the eg is active.
                    LOCAL burnV TO cfma[e][SOidx] / conW[e][SOidx]. // Is larger than 0.
                    IF burnV < minburn { SET minburn TO burnV. }
                    IF dbg {
                        mLog("Found another active SRB in eg "+e+" with burntime "+burnV).
                    }
                }
            }

            SET minburn TO CHOOSE 0 IF minburn = 1e12 ELSE minburn.
            SET btstage TO btstage+minburn.
            IF dbg {
                mLog("s: "+s+" Minimum burn: "+ROUND(minburn,2)).
            }

            IF minburn = 0 {
                IF dbg { mLog("   No burn? Stage! Discard leftover LF fuel."). }
                SET dostage TO True.
            } ELSE {
                // Consume the fuel for minburn.
                LOCAL fuma TO 0. // Fuel consumed
                LOCAL conS TO 0. // Substage consumption
                LOCAL thruVS TO 0. // Substage vacuum thrust
                LOCAL thruAS TO 0. // Substage atmospheric thrust

                // Initialize substage and add burn time.
                sub[s]:ADD(LEXICON("bt", minburn, "con", 0, "thruV", 0, "thruA", 0)).

                IF dbg {
                    mLog(" ").
                    mLog("Consume fuel.").
                }
                FOR e IN actfdstart { // There can be more than one entry.
                    FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                        IF f <> SOidx AND burndu[e][f] > 0 { // Treat SRBs below, only real burns.
                            LOCAL fucon TO 0.
                            LOCAL fuconLF TO 0.

                            LOCAL bs TO burnsrc[e][f].

                            SET fucon TO conW[bs][f]*minburn.
                            SET conS TO conS + conW[bs][f]. // Careful with the bs change below.
                            SET thruVS TO thruVS + thruVW[bs][f].
                            SET thruAS TO thruAS + thruAW[bs][f].

                            // RE can be annoying!
                            IF f = OXidx AND conW[bs][f] > 0 { // Include LF from REs
                                LOCAL bsLF TO burnsrcLF[e][LFidx].
                                SET fuconLF TO conW[bs][f]*ox2lf*minburn.
                                SET conS TO conS + conW[bs][f]*ox2lf.
                                SET cfma[bsLF][LFidx] TO cfma[bsLF][LFidx] - fuconLF.
                                IF ABS(cfma[bsLF][LFidx]) < fuMin {
                                    SET cfma[bsLF][LFidx] TO 0. // Remove rounding errors.
                                }
                                SET fuma TO fuma + fuconLF.
                                IF dbg { mLog(e+",RE LF con: "+ROUND(fuconLF,4)). }
                                // Overwrite bs with OX source eg.
                                SET bs to burnsrcLF[e][OXidx].
                            }
                            SET cfma[bs][f] TO cfma[bs][f] - fucon.
                            IF dbg { mLog(e+","+fuli[f]:SUBSTRING(0,2)+" con:    "+ROUND(fucon,4)). }
                            IF ABS(cfma[bs][f]) < fuMin {
                                SET cfma[bs][f] TO 0. // Remove rounding errors.
                            }
                            IF cfma[bs][f] < 0 {
                                mLog("Fuel: "+ROUND(cfma[bs][f],4)+" in eg,bs,ft: "+e+","+bs+","+f).
                                PRINT 1/0.
                            }
                            SET fuma TO fuma + fucon.
                        }
                    }
                }
                // SRBs don't follow fuel lines - see comment above.
                FROM {local e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
                    // Check first for SRB fuel to shortcut the conditions as fast as possible.
                    IF cfma[e][SOidx] > 0 AND s <= eg[e]:egastage AND s > eg[e]:egdstage  {
                        LOCAL fucon TO conW[e][SOidx]*minburn.
                        SET conS TO conS + conW[e][SOidx].
                        SET thruVS TO thruVS + thruVW[e][SOidx].
                        SET thruAS TO thruAS + thruAW[e][SOidx].
                        IF fucon > cfma[e][SOidx] {
                            // This shouldn't happen. We missed a shorter minimum burn from the SRB.
                            mLog("Missed a shorter SRB minimum burn! Abort!").
                            PRINT 1/0.
                        }
                        IF dbg { mLog(e+": SO con: "+ROUND(fucon,3)). }

                        SET cfma[e][SOidx] TO cfma[e][SOidx] - fucon.
                        SET fuma TO fuma + fucon.
                        IF ABS(cfma[e][SOidx]) < fuMin {
                            SET cfma[e][SOidx] TO 0. // Remove rounding errors.
                        }
                        IF dbg { mLog(e+" SRB: "+nuform(fucon,3,2)). }
                    }
                }

                IF dbg {
                    mLog("Total fuel consumed: "+ROUND(fuma,4)
                        +"  rate: "+ROUND(conS,6)+" ("+ROUND(fuma/minburn,6)+") thrust: "+ROUND(thruVS,3)+" / "+ROUND(thruAS,3)).
                    egFuLog(s).
                    mLog(" ").
                }
                SET stfuel[s] TO stfuel[s] + fuma.
                LOCAL sidx TO sub[s]:LENGTH-1.
                SET sub[s][sidx]:con TO conS.
                SET sub[s][sidx]:thruV TO thruVS.
                SET sub[s][sidx]:thruA TO thruAS.
            }

            // Collect leftover fuel that would get dropped and check if we can stage
            LOCAL nofuel TO True.
            LOCAL hasdropeg TO False.
            LOCAL fuleft TO 0. // Fuel left after burn.
            FROM {LOCAL e is 0.} UNTIL e > eg:LENGTH-1 STEP {set e to e+1.} DO {
                // Assume we can stage, until shown otherwise.
                IF s = eg[e]:egdstage+1 {
                    // Make sure there are stages to drop, e.g. with s = eg[e]:egdstage+1.
                    SET hasdropeg TO True.
                    SET dropeg TO dropeg+" "+e.
                    // Unless there is fuel left in a stage we can stage.
                    LOCAL tfuel TO 0.
                    // Check for fuel and consumption
                    FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                        IF conP[e][f] > 0 {
                            SET tfuel TO tfuel + cfma[e][f].
                            // For RE LF & OX prohibit staging. But avoid double counting LF,
                            IF f = OXidx AND conP[e][LFidx] = 0 { SET tfuel TO tfuel + cfma[e][LFidx]. }
                        }
                        // Collect all fuel left.
                        SET fuleft TO fuleft + cfma[e][f].
                    }
                    IF tfuel > 1e-7 {
                        SET nofuel TO False.
                        IF dbg {
                            mLog("Cannot stage yet. e:"+e+" fuel: "+ROUND(tfuel,3)).
                            mLog(" ").
                        }
                        // Loop over all dropped eg - don't break.
                        //BREAK.
                    }
                }
            }
            IF nofuel AND hasdropeg { SET dostage TO True. }

            IF dbg { mLog("OK to stage - "+dostage). }

            IF dostage {
                SET stburn[s] TO btstage.
                SET stleft[s] TO fuleft.
                IF dbg {
                    mLog("s: "+s+" Burntime: "+ROUND(btstage,2)
                        +" burned: "+ROUND(stfuel[s],3)+" left: "+ROUND(stleft[s],3)).
                }
            } ELSE {
                // Perform setFDfma(e), setConThruFD(e,s) calculation if we are not staging.
                // This is done before the UNTIL loop and needs to be repeated after fuel consumption.
                FOR e IN actfdend { // There can be more than one entry in actfdend.
                    // Set fdfma[e][f] as the cumulative fuel coming into an eg.
                    // Needed for setConThruFD().
                    setFDfma(e).
                    // Set fd con and thru.
                    setConThruFD(e,s).
                }
                egCoFuLog(s).
            }
        }
    }

    // Needs to move to the end
    // Finds source eg for OXsrc and LFsrc
    FUNCTION getREsrc {
        PARAMETER e.    // Engine group

        LOCAL LFre TO CHOOSE e IF cfma[e][LFidx] > 0 ELSE -1.
        LOCAL OXre TO CHOOSE e IF cfma[e][OXidx] > 0 ELSE -1.

        FOR es IN eg[e]:actfdsrc {
            //mLog("Call e: "+e+" -> es: "+es).
            LOCAL rval TO getREsrc(es).
            IF rval[0] >= 0 AND cfma[rval[0]][LFidx] > fuMin {
                SET LFre TO rval[0].
                //mLog("LF es: "+es+" ret: "+LFre).
            }
            IF rval[1] >= 0 AND cfma[rval[1]][OXidx] > fuMin {
                SET OXre TO rval[1].
                //mLog("OX es: "+es+" ret: "+OXre).
            }
        }
        RETURN LIST(LFre,OXre).
    }

    // Needs to move to the end
    // Calculates how much fuel is available in eg including incoming fuel ducts.
    FUNCTION setFDfma {
        PARAMETER e.    // Engine group

        FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
            SET fdfma[e][f] TO cfma[e][f].
        }
        FOR es IN eg[e]:actfdsrc {
            setFDfma(es).
            FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                // Solid fuel doesn't flow through fuel ducts.
                IF f <> SOidx {
                    SET fdfma[e][f] TO fdfma[e][f] + fdfma[es][f].
                }
            }
        }
        RETURN 1.
    }

    // Needs to move to the end
    // Calculates consumption and thrust based on locally available fuel and downstream fd connections.
    FUNCTION setConThruFD {
        PARAMETER e,    // Engine group
                  s.    // Stage

        FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
            SET conP[e][f] TO con[e][s][f]. // Potential consumption
            // Use fdfma instead of cfma. This loop works end to source.
            IF fdfma[e][f] > 0 AND ( f <> OXidx OR fdfma[e][LFidx] > 0 ) {
                // RE needs both
                SET conW[e][f] TO con[e][s][f].
                SET thruVW[e][f] TO thruV[e][s][f].
                SET thruAW[e][f] TO thruA[e][s][f].
            } ELSE {
                SET conW[e][f] TO 0.
                SET thruVW[e][f] TO 0.
                SET thruAW[e][f] TO 0.
            }
        }

        // Find active sources per fuel for current eg.
        // Loop over eg that feed into this one. If there is (cumulative) fuel increase the "feeder" count.
        SET fdnum[e] TO fuliZ:COPY.
        FOR es IN eg[e]:actfdsrc {
            FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                IF fdfma[es][f] > 0 {
                    IF f = OXidx AND fdfma[es][LFidx] = 0 {
                        // RE need both, so don't set conW
                    } ELSE {
                        SET fdnum[e][f] TO fdnum[e][f]+1.
                    }
                }
            }
        }
        // This uses fdnum from downstream eg.
        // Calculate consumption for the current eg, including the consuption of all downstream eg that have
        // fuel feeding into them. We only can use the con if we have fuel ourselves.
        FOR ed IN eg[e]:actfddest { // Can be 0 or 1 entries.
            FROM {LOCAL f is 0.} UNTIL f > fuli:LENGTH-1 STEP {set f to f+1.} DO {
                // Solid fuel doesn't flow through fuel ducts.
                IF f <> SOidx AND fdnum[ed][f] > 0 AND fdfma[e][f] > 0 {
                    IF f <> OXidx OR fdfma[e][LFidx] > 0 {
                        // RE need both, so don't set conW otherwise.
                        SET conW[e][f] TO conW[e][f] + conW[ed][f] / fdnum[ed][f].
                        SET thruVW[e][f] TO thruVW[e][f] + thruVW[ed][f] / fdnum[ed][f].
                        SET thruAW[e][f] TO thruAW[e][f] + thruAW[ed][f] / fdnum[ed][f].
                    }
                }
                // This indicates if there is a consumer for the fuel type. The value of conP is
                // not meaningfull. Zero means nothing, otherwise there is consumption.
                SET conP[e][f] TO conP[e][f] + conP[ed][f].
            }
        }
        // Recursion.
        FOR ee IN eg[e]:actfdsrc {
            setConThruFD(ee,s).
        }

        RETURN 1.
    }

    // Print/Log consumption, thrust and mass info for all egs, s and f
    egLog().

    // 6. Final loop, calculated cumulative mass and other derived values, like
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
        LOCAL fuleft TO stleft[s]. // Fuel left and to be discarded at the end of the stage.
        LOCAL fuburn TO stfuel[s]. // Fuel burned in stage
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
            mLog("i,bt,con,thruV,thruA,ispsV,sfubu,subVdV,subAdV,curmass,submass").
        }
        FROM {LOCAL i is 0.} UNTIL i > sub[s]:LENGTH-1 STEP {set i to i+1.} DO {
            LOCAL fcon TO sub[s][i]:con.
            LOCAL fthruV TO sub[s][i]:thruV.
            LOCAL fthruA TO sub[s][i]:thruA.
            LOCAL ispsV TO fthruV/fcon/CONSTANT:g0.
            LOCAL ispsC TO fthruA/fcon/CONSTANT:g0.
            LOCAL subfubu TO fcon*sub[s][i]:bt. // Fuel burned in substage
            SET stfubu TO stfubu + subfubu.
            LOCAL submass TO curmass - subfubu. // Mass at end of current substage
            SET maxTWR TO MAX(maxTWR, sub[s][i]:thruV/submass/CONSTANT:g0).
            SET maxSLT TO MAX(maxSLT, sub[s][i]:thruA/submass/CONSTANT:g0).
            LOCAL subVdV TO ispsV*CONSTANT:g0*LN(curmass/submass).
            LOCAL subAdV TO ispsC*CONSTANT:g0*LN(curmass/submass).
            SET stVdV TO stVdV + subVdV.
            SET stAdV TO stAdV + subAdV.
            IF dbg { mLog(i+","+nuform(sub[s][i]:bt,3,1)+","+nuform(fcon,1,5)+","+nuform(fthruV,3,2)+","
                +nuform(fthruA,3,2)+","+nuform(ispsV,3,0)+","+nuform(subfubu,3,2)+","+nuform(subVdV,4,0)
                          +","+nuform(subAdV,4,0)+","+nuform(curmass,3,2)+","+nuform(submass,3,2)). }
            SET curmass TO submass. // The next substage starts with the current substge end mass.
        }
        LOCAL KERispV TO 0. // ISPg0 vac like MJ/KER uses
        LOCAL KERispA TO 0. // ISPg0 sea level like MJ/KER uses
        IF stVdV {
            SET KERispV TO stVdV/CONSTANT:g0/LN(startmass/endmass).
            SET KERispA TO stAdV/CONSTANT:g0/LN(startmass/endmass).
        }
        // Sanity check
        IF stburn[s] > 0 AND ABS(1-stfubu/fuburn) > 0.0001 {
            mLog(" ").
            mLog("Check fuel burned! Substage cumulative: "+stfubu+" Stage: "+fuburn).
            mLog(" ").
        }

        LOCAL KSPispV IS 0.
        LOCAL KSPispA IS 0.
        LOCAL thruV IS stithruV[s].// Thrust in stage (vacuum).
        LOCAL thruA IS stithruA[s].// Thrust in stage (current position).
        IF fuburn = 0 {
            SET thruV TO 0.
            SET thruA TO 0.
        }
        // Note: We cannot average over different burn times. Use sub-stages by burn time.
        IF sticon[s] > 0 {
            SET KSPispV TO thruV/sticon[s]/CONSTANT:g0.
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
        SET sinfo["KSPispV"] TO KSPispV.
        SET sinfo["KERispV"] TO KERispV.
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
                +nuform(KSPispV,4,2)+","+nuform(KERispV,4,2)+","+nuform(sTWR,3,3)+","+nuform(maxTWR,3,3)+","
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
        // egli, egtali, egfdli, egastage, egdstage.
        // In procli all parts that have been assigned to an eg will be remembered.
        // The function returns False if the first part it gets called on is already in an engine group.
        PARAMETER p,    // Part node.
                l.      // Recursion level, child increases, parent decreases. Only for info.

        IF procli:CONTAINS(p:UID) {
            IF dbg { mLog("   - Already processed!"). }
            RETURN False.
        }

        LOCAL xfeed TO True. // For parts where crossfeed can be modified.
        LOCAL is_ep TO False. // True for engine plates.
        LOCAL stopWalk TO False. // Stop recursion when true.

        IF p:MASS > p:DRYMASS or p:TYPENAME = "Engine" {
            //IF dbg { mLog("Found engine or tank."). }
            egtali:ADD(p).
            // Find earliest egastage and egdstage for engines.
            IF p:TYPENAME = "Engine" {
                // This should only trigger for egs with decouplers with crossfeed on or if engines attached
                // to the same group are activated at different stages.

                LOCAL pastage TO p:STAGE. // Stage when part becomes active
                IF pastage > egastage {
                    IF dbg { mLog("   - Change egastage from "+egastage+" to "+pastage). }
                    SET egastage TO pastage.
                }
                LOCAL pdstage TO Ep_Decoupledin(p). // Stage when part has been removed
                // This could happen for decouplers with crossfeed enabled.
                IF pdstage < egdstage {
                    IF dbg { mLog("   - Change egdstage from "+egdstage+" to "+pdstage). }
                    SET egdstage TO pdstage.
                }
            }
        }

        IF p:NAME = "fuelLine" {
            egfdli:ADD(p).
        }.

        IF p:HASMODULE("ModuleToggleCrossfeed") {
            // Default for xfeed is True
            IF p:GETMODULE("ModuleToggleCrossfeed"):HASEVENT("enable crossfeed") {
                SET xfeed TO False.
                IF dbg { mLog("     Found "+p:TITLE+" with crossfeed: "+xfeed). }
            }
        }

        IF dectyp:CONTAINS(p:TYPENAME) {
            IF p:NAME:STARTSWITH("EnginePlate") {
                // Engine plates don't have a ModuleToggleCrossfeed, they never have crossfeed
                // when staging is enabled.
                SET is_ep TO True.
                // See below. Keep xfeed True, even though that's redundant.
            }
            IF xfeed OR is_ep {
                // One engine group, just traverse through it. EPs get special treatment below.
                IF dbg { mLog("   Traversing through decoupler or engine plate."). }
            } ELSE {
                // kOS has no way to find out which side a decoupler (or similar) stays attached to.
                // The mass is assigned in loop 2, the assignment to a specific engine group doesn't
                // matter. We assign it to the current group.
                // This also includes decouplers only attached to only one side.
                IF dbg { mLog("   Decoupler! Do not traverse."). }
                // Do not traverse through decoupler.
                SET stopWalk TO True.
            }
        }

        IF p:TYPENAME = "DockingPort" AND p:HASMODULE("ModuleDockingNode") {
            // Docking ports can act as decouplers. Treat them accordingly.
            IF p:GETMODULE("ModuleDockingNode"):HASEVENT("port: disable staging") {
                IF p:GETMODULE("ModuleDockingNode"):HASEVENT("disable crossfeed") {
                    // One engine group, just traverse through it.
                    IF dbg { mLog("   Traversing through docking port. Crossfeed enabled"). }
                } ELSE {
                    IF dbg { mLog("   Docking port with staging on and crossfeed off! Do not traverse."). }
                    SET stopWalk TO True.
                }
            }
        }

        // Add part to this eg
        procli:ADD(p:UID).
        egli:ADD(p).
        IF dbg { mLog(Ep_Decoupledin(p)+","+p:STAGE+","+p:TITLE+","+p:NAME+","+p:TYPENAME+","+l). }

        // The following parts have no Crossfeed. Stop the "walk" here.
        IF nocflist:CONTAINS(p:NAME) {
            IF dbg { mLog("   Found "+p:TITLE+" with crossfeed: "+False). }
            SET stopWalk TO True.
        }

        IF stopWalk { RETURN True. }

        // Engine plates are problematic. See "Problems and additional considerations" at the beginning
        // of the file. Use the following approach:
        // If the part is an engine plate, first check if the [dependent]:DECOUPLER value is the same as
        // the engime plates value. If yes, they are in the same eg. (The "top" node is correct). Otherwise
        // for engine plates going to attached parts check the following 3 conditions in that order:
        // If the dependent part has/is ..
        // - kOS tag starting with "epa": Assume part is in same eg, call eTree().
        // - kOS tag starting with "epd": Assume part is decoupled, don't call eTree().
        // - an engine: Assume part is attached, call eTree()
        // - nothing of the above, assume it is decoupled, don't call eTree().
        // For parts going to engine plates check for the corresponding conditions:
        // (extrapolate from above)
        FOR child IN p:CHILDREN {
            IF is_ep {
                LOCAL kTag TO child:GETMODULE("KOSNameTag"):GETFIELD("name tag").
                IF child:DECOUPLER = p:DECOUPLER {
                    IF dbg { mLog("   C: check: "+child:TITLE+" / to ep top node"). }
                    eTree(child,l+1).
                } ELSE IF kTag:STARTSWITH("epa") {
                    IF dbg { mLog("   C: check: "+child:TITLE+" / epa"). }
                    eTree(child,l+1).
                } ELSE IF kTag:STARTSWITH("epd") {
                    IF dbg { mLog("   C: skip: "+child:TITLE+" / epd"). }
                } ELSE IF child:TYPENAME = "Engine"{
                    IF dbg { mLog("   C: check: "+child:TITLE+" / engine"). }
                    eTree(child,l+1).
                } ELSE {
                    IF dbg { mLog("   C: skip: "+child:TITLE+" / assume epd"). }
                }
            } ELSE IF dectyp:CONTAINS(child:TYPENAME) AND child:NAME:STARTSWITH("EnginePlate") {
                // Check if we go to EP. Go only if we are an engine, epa is set, or epd is not set.
                LOCAL kTag TO p:GETMODULE("KOSNameTag"):GETFIELD("name tag").
                IF child:DECOUPLER = p:DECOUPLER {
                    IF dbg { mLog("   C: check: "+child:TITLE+" / from ep top node"). }
                    eTree(child,l+1).
                } ELSE IF kTag:STARTSWITH("epa") {
                    IF dbg { mLog("   C: check: "+child:TITLE+" / from epa"). }
                    eTree(child,l+1).
                } ELSE IF kTag:STARTSWITH("epd") {
                    IF dbg { mLog("   C: skip: "+child:TITLE+" / from epd"). }
                } ELSE IF p:TYPENAME = "Engine" {
                    IF dbg { mLog("   C: check: "+child:TITLE+" / from engine"). }
                    eTree(child,l+1).
                } ELSE {
                    IF dbg { mLog("   C: skip: "+child:TITLE+" / from ep assume epd"). }
                }
            } ELSE {
                // Not an engine plate, and not going to one. Check for attachment to eg.
                IF dbg { mLog("   C: check: "+child:TITLE). }
                eTree(child,l+1).
            }
        }
        IF p:HASPARENT {
            IF is_ep {
                LOCAL kTag TO p:PARENT:GETMODULE("KOSNameTag"):GETFIELD("name tag").
                IF p:PARENT:DECOUPLER = p:DECOUPLER {
                    IF dbg { mLog("   P: check: "+p:PARENT:TITLE+" / to ep top node"). }
                    eTree(p:PARENT,l+1).
                } ELSE IF kTag:STARTSWITH("epa") {
                    IF dbg { mLog("   P: check: "+p:PARENT:TITLE+" / epa"). }
                    eTree(p:PARENT,l+1).
                } ELSE IF kTag:STARTSWITH("epd") {
                    IF dbg { mLog("   P: skip: "+p:PARENT:TITLE+" / epd"). }
                } ELSE IF p:PARENT:TYPENAME = "Engine" {
                    IF dbg { mLog("   P: check: "+p:PARENT:TITLE+" / engine"). }
                    eTree(p:PARENT,l+1).
                } ELSE {
                    IF dbg { mLog("   P: skip: "+p:PARENT:TITLE+" / no-epa"). }
                }
            } ELSE IF dectyp:CONTAINS(p:PARENT:TYPENAME) AND p:PARENT:NAME:STARTSWITH("EnginePlate"){
                // Check if we go to EP. Go only if we are an engine, epa is set, or epd is not set.
                LOCAL kTag TO p:GETMODULE("KOSNameTag"):GETFIELD("name tag").
                IF p:PARENT:DECOUPLER = p:DECOUPLER {
                    IF dbg { mLog("   P: check: "+p:PARENT:TITLE+" / from ep top node"). }
                    eTree(p:PARENT,l+1).
                } ELSE IF kTag:STARTSWITH("epa") {
                    IF dbg { mLog("   P: check: "+p:PARENT:TITLE+" / from epa"). }
                    eTree(p:PARENT,l+1).
                } ELSE IF kTag:STARTSWITH("epd") {
                    IF dbg { mLog("   P: skip: "+p:PARENT:TITLE+" / from epd"). }
                } ELSE IF p:TYPENAME = "Engine" {
                    IF dbg { mLog("   P: check: "+p:PARENT:TITLE+" / from engine"). }
                    eTree(p:PARENT,l+1).
                } ELSE {
                    IF dbg { mLog("   P: skip: "+p:PARENT:TITLE+" / from ep assume epd"). }
                }
            } ELSE {
                // Not an engine plate, and not going to one. Check for attachment to eg.
                IF dbg { mLog("   P: check: "+p:PARENT:TITLE). }
                eTree(p:PARENT,l+1).
            }
        }

        RETURN True.
    }


    FUNCTION setConThru {
        PARAMETER x,    // Part node.
                  i.    // Engine group.

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

        LOCAL tlimit IS x:THRUSTLIMIT/100. // Needed to adjust res:MAXMASSFLOW
        IF dbg { mLog("Engine: "+x:TITLE+" "+x:STAGE+" "+Ep_Decoupledin(x)). }
        FOR fkey IN x:CONSUMEDRESOURCES:KEYS { // fkey is language localized display name
            LOCAL cRes TO x:CONSUMEDRESOURCES[fkey]. // Consumed resource
            LOCAL fname TO cRes:NAME. // Workaround for bug. fname not localized (language)
            LOCAL fti TO fuli:FIND(fname).
            // Sanity check if our engine consumes something else than fuli
            IF fti >= 0 {
                // Set con[fti]
                SET conF[fti] TO cRes:MAXMASSFLOW*tlimit.
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

        // Now add fuel consumption and thrust to the applicable stages.
        // This also adds the LF mass consumption correction for REs.
        FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
            IF s <= x:STAGE AND s > Ep_Decoupledin(x) {
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
            }
            // It is wrong to add zeroes (especially with fuliZ:COPY) as other engines in this eg
            // can have different x:STAGE or x:DECOUPLEDIN values. The xx[i][s][x] lists are initialized
            // to zero intitially.
        }
    }


    FUNCTION egLog {
        // Loop over engine groups - for printing con, thruV and thruA
        IF dbg {
            mLog(" ").
            mLog("Eg info").
            FROM {local i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
                // For printing
                mLog("Eg: "+i+" egastage: "+eg[i]:egastage).
                mLog("s,con                            ,thruV                              "
                     +",thruA").
                FROM {LOCAL s IS 0.} UNTIL s > STAGE:NUMBER STEP {SET s TO s+1.} DO {
                    LOCAL scon TO "".
                    LOCAL sthruV TO "".
                    LOCAL sthruA TO "".
                    LOCAL x TO 0.
                    UNTIL x >= fuli:LENGTH {
                        LOCAL cW TO con[i][s][x].
                        IF x = XEidx { SET cW TO cW*1000. } // Xenon needs a boost.
                        SET scon TO scon+","+nuform(cW,3,3).
                        SET sthruV TO sthruV+","+nuform(thruV[i][s][x],4,2).
                        SET sthruA TO sthruA+","+nuform(thruA[i][s][x],4,2).
                        SET x to x + 1.
                    }
                    mLog(s+scon+sthruV+sthruA).
                }
            }
        }
    }

    FUNCTION egFuLog {
        PARAMETER s.    // Stage.
        // Loop over engine groups - for printing cfma
        IF dbg {
            mLog("Eg info - Stage: "+s).
            mLog("eg,as,ds,cfma").
            FROM {local i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
                // For printing
                IF s > eg[i]:egdstage {
                        LOCAL scfma TO "".
                        LOCAL x TO 0.
                        UNTIL x >= fuli:LENGTH {
                            SET scfma TO scfma+","+nuform(cfma[i][x],3,2).
                            SET x to x + 1.
                        }
                        mLog(nuform(i,2,0)+","+nuform(eg[i]:egastage,2,0)+","+nuform(eg[i]:egdstage,2,0)+scfma).
                }
            }
        }
    }

    FUNCTION egCoFuLog {
        PARAMETER s.    // Stage.
        // Loop over engine groups - for printing conW, fdfma, fdnum
        IF dbg {
            mLog("eg,as,ds,conW                       ,conP                       ,fdfma                      ,fdnum").
            FROM {local i is 0.} UNTIL i > eg:LENGTH-1 STEP {set i to i+1.} DO {
                // For printing
                IF s > eg[i]:egdstage {
                        LOCAL sconW TO "".
                        LOCAL sconP TO "".
                        LOCAL sfdfma TO "".
                        LOCAL sfdnum TO "".
                        LOCAL x TO 0.
                        UNTIL x >= fuli:LENGTH {
                            LOCAL cW TO conW[i][x].
                            LOCAL cP TO conP[i][x].
                            IF x = XEidx { SET cW TO cW*1000. SET cP TO cP*1000. } // Xenon needs a boost.
                            SET sconW TO sconW+","+nuform(cW,2,3).
                            SET sconP TO sconP+","+nuform(cP,2,3).
                            SET sfdfma TO sfdfma+","+nuform(fdfma[i][x],3,2).
                            SET sfdnum TO sfdnum+","+nuform(fdnum[i][x],2,0).
                            SET x to x + 1.
                        }
                        mLog(nuform(i,2,0)+","+nuform(eg[i]:egastage,2,0)+","+nuform(eg[i]:egdstage,2,0)
                             +sconW+sconP+sfdfma+sfdnum).
                }
            }
        }
    }

    FUNCTION Ep_Decoupledin {
        PARAMETER p.    // Part.
        // All parts attached to engine plates and their dependents, except the ones attached
        // attached to the "decoupled node" or the "top node" do not have their DECOUPLEDIN set correctly.
        // Use the value of the engine plate instead.
        // These parts can be identified by p:DECOUPLER linking to engine plate. The "top node" does not
        // need to be considered differently, as it is covered by p:DECOUPLER another decoupler.

        LOCAL pDE TO p:DECOUPLER.
        IF pDE:TYPENAME <> "String" AND pDE:NAME:STARTSWITH("EnginePlate") {
            // Dependent of an active engine plate
            LOCAL kTag TO p:GETMODULE("KOSNameTag"):GETFIELD("name tag").
            IF kTag:STARTSWITH("epa") {
                // EP attached
                RETURN pDE:DECOUPLEDIN.
            } ELSE IF kTag:STARTSWITH("epd") {
                // Part is on decoupled side
                RETURN p:DECOUPLEDIN.
            } ELSE IF p:TYPENAME = "Engine"
                      AND ( p:PARENT = pDE OR p:CHILDREN:CONTAINS(pDE)  ) {
                // Engine is directly attached to the engine plate.
                RETURN pDE:DECOUPLEDIN.
            } ELSE {
                // No special case, assume part is on the decoupled side.
                RETURN p:DECOUPLEDIN.
            }
        } ELSE {
            // Not decoupled from an engine plate
            RETURN p:DECOUPLEDIN.
        }
    }

}
