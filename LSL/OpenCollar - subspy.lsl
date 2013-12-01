////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------ //
//                              OpenCollar - subspy                               //
//                                 version 3.936                                  //
// ------------------------------------------------------------------------------ //
// Licensed under the GPLv2 with additional requirements specific to Second Life® //
// and other virtual metaverse environments.  ->  www.opencollar.at/license.html  //
// ------------------------------------------------------------------------------ //
// ©   2008 - 2013  Individual Contributors and OpenCollar - submission set free™ //
// ------------------------------------------------------------------------------ //
////////////////////////////////////////////////////////////////////////////////////

//modified by: Zopf Resident - Ray Zopf (Raz)
//Additions: changes on save settings, small bugfixes, added reset on runaway, warning on startup; better handling of para rp
//07. Nov 2013
//
//Files:
//OpenCollar - subspy.lsl
//
//Prequisites: OC
//Notecard format: ---
//basic help:

//bug: ???
//bug: heap collision on too much chat text

//todo: rework link_message{}
//todo: rework listener reporting, currently much text is just discarded
///////////////////////////////////////////////////////////////////////////////////////////////////



//===============================================
//FIRESTORM SPECIFIC DEBUG STUFF
//===============================================

//#define FSDEBUG
//#include "fs_debug.lsl"


//===============================================
//GLOBAL VARIABLES
//===============================================

//debug variables
//-----------------------------------------------

integer g_iDebugMode=FALSE; // set to TRUE to enable Debug messages


//internal variables
//-----------------------------------------------

//put all reporting on an interval of 30 or 60 secs.  That way we won't get behind with IM delays.
//use sensorrepeat as a second timer to do the reporting (since regular timer is already used by menu system
//if radar is turned off, just don't report avs when the sensor or no_sensor event goes off

list g_lAvBuffer;//if this changes between report intervals then tell owners (if radar enabled)
list g_lChatBuffer;//if this has anything in it at end of interval, then tell owners (if listen enabled)
list g_lTPBuffer;//if this has anything in it at end of interval, then tell owners (if trace enabled)

string g_sOldAVBuffer; // AVs previously found, only send radar if this has changed
integer g_iOldAVBufferCount = -1; // number of AVs previously found, only send radar if this has changed, setting to -1 at startup

list g_lCmds = ["trace on","trace off", "radar on", "radar off", "listen on", "listen off"];
integer g_iListenCap = 1000;//throw away old chat lines once we reach this many chars, to prevent stack/heap collisions
integer g_iReportChar = 450;
integer g_iListener;
string g_sOffMsg = "Spy add-on is now disabled";

string g_sLoc;
integer g_iFirstReport = TRUE;//if this is true when spy settings come in, then record current position in g_lTPBuffer and set to false
integer g_iSensorRange = 4;
integer g_iSensorRepeat = 900;

//OC MESSAGE MAP
//integer COMMAND_NOAUTH = 0;
integer COMMAND_OWNER = 500;
integer COMMAND_SECOWNER = 501;
integer COMMAND_GROUP = 502;
integer COMMAND_WEARER = 503;
integer COMMAND_EVERYONE = 504;
integer COMMAND_SAFEWORD = 510;  // new for safeword

//integer SEND_IM = 1000; deprecated.  each script should send its own IMs now.
integer POPUP_HELP = 1001;

integer LM_SETTING_SAVE = 2000;//scripts send messages on this channel to have settings saved to httpdb
//str must be in form of "token=value"
integer LM_SETTING_REQUEST = 2001;//when startup, scripts send requests for settings on this channel
integer LM_SETTING_RESPONSE = 2002;//the httpdb script will send responses on this channel
integer LM_SETTING_DELETE = 2003;//delete token from DB
integer LM_SETTING_EMPTY = 2004;//sent when a token has no value in the httpdb

integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer MENUNAME_REMOVE = 3003;

integer DIALOG = -9000;
integer DIALOG_RESPONSE = -9001;
integer DIALOG_TIMEOUT = -9002;

string g_sScript;

string UPMENU = "BACK";
string g_sParentMenu = "AddOns";
string g_sSubMenu = "SubSpy";

list g_lOwners;
string g_sSubName;
list g_lSettings;

key g_kDialogSpyID;
key g_kDialogRadarSettingsID;

key g_kWearer;


//===============================================
//PREDEFINED FUNCTIONS
//===============================================


//===============================================================================
//= parameters   :    string    sMsg    message string received
//=
//= return        :    none
//=
//= description  :    output debug messages
//=
//===============================================================================

Debug(string sMsg)
{
    if (!g_iDebugMode) return;
    Notify(g_kWearer,llGetScriptName() + ": " + sMsg,TRUE);
}


string GetScriptID()
{
    // strip away "OpenCollar - " leaving the script's individual name
    list parts = llParseString2List(llGetScriptName(), ["-"], []);
    return llStringTrim(llList2String(parts, 1), STRING_TRIM) + "_";
}


string PeelToken(string in, integer slot)
{
    integer i = llSubStringIndex(in, "_");
    if (!slot) return llGetSubString(in, 0, i);
    return llGetSubString(in, i + 1, -1);
}


DoReports(integer iBufferFull)
{
    Debug("doing reports, iBufferFull: "+(string)iBufferFull);
    //build a report containing:
    //who is nearby (as listed in g_lAvBuffer)
    //where the sub has TPed (s stored in g_lTPBuffer)
    //what the sub has sakID (as stored in g_lChatBuffer)
    string sReport;

    if (Enabled("radar") && !iBufferFull)
    {
        //Debug("Old: "+(string)g_iOldAVBufferCount+";"+g_sOldAVBuffer);
        integer kAvcount = llGetListLength(g_lAvBuffer);
        //Debug("New: "+(string)kAvcount+";"+llDumpList2String(llListSort(g_lAvBuffer, 1, TRUE), ", "));
        if (kAvcount != g_iOldAVBufferCount)
        {
            if (kAvcount)
            {
                g_sOldAVBuffer = llDumpList2String(llListSort(g_lAvBuffer, 1, TRUE), ", ");
                sReport += "\nNearby avatars: " + g_sOldAVBuffer + ".";

            }
            else
            {
                sReport += "\nNo nearby avatars.";
                g_sOldAVBuffer = "";
            }
            g_iOldAVBufferCount = kAvcount;
        }
        else
        {
            string sCurrentAVs = llDumpList2String(llListSort(g_lAvBuffer, 1, TRUE), ", ");
            if (sCurrentAVs != g_sOldAVBuffer)
            {
                g_sOldAVBuffer = sCurrentAVs;
                if (kAvcount)
                {
                    sReport += "\nNearby avatars: " + g_sOldAVBuffer + ".";
                }
            }
        }
    }

    if (Enabled("trace") && !iBufferFull)
    {
        integer iLength = llGetListLength(g_lTPBuffer);
        if (iLength)
        {
            sReport += "\n" + llDumpList2String(["Login/TP info:"] + g_lTPBuffer, "\n--");
        }
    }

    if (Enabled("listen"))
    {
        integer iLength = llGetListLength(g_lChatBuffer);
        if (iLength)
        {
            sReport += "\n" + llDumpList2String(["Chat:"] + g_lChatBuffer, "\n--");
        }
    }

    if (llStringLength(sReport))
    {
        sReport = "Activity report for " + g_sSubName + " at " + GetTimestamp() + sReport;
        Debug("report: " + sReport);
        NotifyOwners(sReport);
    }

    //flush buffers
	Debug("flush buffers");
    if (!iBufferFull) g_lAvBuffer = [];
    g_lChatBuffer = [];
    if (!iBufferFull) g_lTPBuffer = [];
}


UpdateSensor()
{
    llSensorRemove();
    //since we use the repeating sensor as a timer, turn it on if any of the spy reports are turned on, not just radar
    //also, only start the sensor/timer if we're attached so there's no spam from collars left lying around
    if (llGetAttached() && Enabled("trace") || Enabled("radar") || Enabled("listen"))
    {
        Debug("enabling sensor");
        llSensorRepeat("" ,"" , AGENT, g_iSensorRange, PI, g_iSensorRepeat);
    }
}


UpdateListener()
{
    Debug("updatelistener");
    if (llGetAttached())
    {
        if (Enabled("listen"))
        {
            //turn on listener if not already on
            if (!g_iListener)
            {
                Debug("turning listener on");
                g_iListener = llListen(0, "", g_kWearer, "");
            }
        }
        else
        {
            //turn off listener if on
            if (g_iListener)
            {
                Debug("turning listener off");
                llListenRemove(g_iListener);
                g_iListener = 0;
            }
        }
    }
    else
    {
        //we're not attached.  close listener
        Debug("turning listener off");
        llListenRemove(g_iListener);
        g_iListener = 0;
    }
}


integer Enabled(string sToken)
{
    integer iIndex = llListFindList(g_lSettings, [sToken]);
    Debug("enabled; Settings: "+(string)g_lSettings + " Token: "+ sToken + " -- Position: " + (string)iIndex);
    if(iIndex == -1)
    {
        return FALSE;
    }
    else
    {
        if(llList2String(g_lSettings, iIndex + 1) == "on")
        {
            return TRUE;
        }
        return FALSE;
    }
}


string GetTimestamp() // Return a string of the date and time
{
    integer t = (integer)llGetWallclock(); // seconds since midnight

    return GetPSTDate() + " " + (string)(t / 3600) + ":" + PadNum((t % 3600) / 60) + ":" + PadNum(t % 60);
}


string PadNum(integer sValue)
{
    if(sValue < 10)
    {
        return "0" + (string)sValue;
    }
    return (string)sValue;
}


string GetPSTDate()
{ //Convert the date from UTC to PST if GMT time is less than 8 hours after midnight (and therefore tomorow's date).
    string sDateUTC = llGetDate();
    if (llGetGMTclock() < 28800) // that's 28800 seconds, a.k.a. 8 hours.
    {
        list lDateList = llParseString2List(sDateUTC, ["-", "-"], []);
        integer iYear = llList2Integer(lDateList, 0);
        integer iMonth = llList2Integer(lDateList, 1);
        integer iDay = llList2Integer(lDateList, 2);
        iDay = iDay - 1;
        return (string)iYear + "-" + (string)iMonth + "-" + (string)iDay;
    }
    return llGetDate();
}


string GetLocation() {
    vector g_vPos = llGetPos();
    return llList2String(llGetParcelDetails(llGetPos(), [PARCEL_DETAILS_NAME]),0) + " (" + llGetRegionName() + " <" +
        (string)((integer)g_vPos.x)+","+(string)((integer)g_vPos.y)+","+(string)((integer)g_vPos.z)+">)";
}


key Dialog(key kRCPT, string sPrompt, list lChoices, list lUtilityButtons, integer iPage, integer iAuth)
{
    key kID = llGenerateKey();
    llMessageLinked(LINK_SET, DIALOG, (string)kRCPT + "|" + sPrompt + "|" + (string)iPage + "|" 
    + llDumpList2String(lChoices, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kID);
    return kID;
} 


DialogSpy(key kID, integer iAuth)
{
    string sPrompt;
    if (iAuth != COMMAND_OWNER)
    {
        sPrompt = "\n\nACCESS DENIED: Primary Owners Only";
        g_kDialogSpyID = Dialog(kID, sPrompt, [], [UPMENU], 0, iAuth);
        return;
    }
    list lButtons ;
    sPrompt = "\n\n- Access Granted to Primary Owners Only -\n";
    sPrompt += "\nTrace notifies if " + g_sSubName + " teleports.\n";
    sPrompt += "\nRadar and Listen sending reports every "+ (string)((integer)g_iSensorRepeat/60) + " minutes on who joined or left " + g_sSubName + " in a range of " + (string)((integer)g_iSensorRange) + " meters and on what " + g_sSubName + " wrote in Nearby Chat.\n";
    sPrompt += "\nListen transmits directly what " + g_sSubName + " says in Nearby Chat. Other nearby parties chat will NOT be transmitted!\n - Messages may get capped and not all text may get transmitted -";

    if(Enabled("trace"))
    {
        lButtons += ["Trace Off"];
    }
    else
    {
        lButtons += ["Trace On"];
    }
    if(Enabled("radar"))
    {
        lButtons += ["Radar Off"];
    }
    else
    {
        lButtons += ["Radar On"];
    }
    if(Enabled("listen"))
    {
        lButtons += ["Listen Off"];
    }
    else
    {
        lButtons += ["Listen On"];
    }
    lButtons += ["RadarSettings"];
    g_kDialogSpyID = Dialog(kID, sPrompt, lButtons, [UPMENU], 0, iAuth);
}


DialogRadarSettings(key kID, integer iAuth)
{
    list lButtons;
    string sPromt = "\n\nSetup for the Radar Repeats, Sensors and Report Frequency:\n";
    sPromt += "\nRadar Range is set to: " + (string)((integer)g_iSensorRange) + " meters.\n";
    sPromt += "\nRadar and Listen report frequency is set to: " + (string)((integer)g_iSensorRepeat/60) + " minutes.\n";
    lButtons += ["4 meters", "8 meters", "18 meters"];
    lButtons += ["5 minutes", "9 minutes", "15 minutes", "21 minutes"];
    g_kDialogRadarSettingsID = Dialog(kID, sPromt, lButtons, [UPMENU], 0, iAuth);
}


integer GetOwnerChannel(key kOwner, integer iOffset)
{
    integer iChan = (integer)("0x"+llGetSubString((string)kOwner,2,7)) + iOffset;
    if (iChan>0)
    {
        iChan=iChan*(-1);
    }
    if (iChan > -10000)
    {
        iChan -= 30000;
    }
    return iChan;
}


Notify(key kID, string sMsg, integer iAlsoNotifyWearer)
{
    if (kID == g_kWearer)
    {
        llOwnerSay(sMsg);
    }
    else if (llGetAgentSize(kID) == ZERO_VECTOR)
    {
        llInstantMessage(kID,sMsg);
        if (iAlsoNotifyWearer)
        {
            llOwnerSay(sMsg);
        }
    }
    else // remote request
    {
        llRegionSayTo(kID, GetOwnerChannel(g_kWearer, 1111), sMsg);
    }
}


BigNotify(key kID, string sMsg)
{//if sMsg iLength > 1024, split into bite sized pieces and IM each individually
    Debug("bignotify");
    list g_iLines = llParseString2List(sMsg, ["\n"], []);
    while (llGetListLength(g_iLines))
    {
        Debug("looping through lines");
        //build a string with length up to the IM limit, with a little wiggle room
        list lTmp;
        while (llStringLength(llDumpList2String(lTmp, "\n")) < 800 && llGetListLength(g_iLines))
        {
            Debug("building a line");
            lTmp += llList2List(g_iLines, 0, 0);
            g_iLines = llDeleteSubList(g_iLines, 0, 0);
        }
        Notify(kID, llDumpList2String(lTmp, "\n"), FALSE);
    }
}


NotifyOwners(string sMsg)
{
    Debug("notifyowners");
    integer n;
    integer iStop = llGetListLength(g_lOwners);
    for (n = 0; n < iStop; n += 2)
    {
        key kAv = (key)llList2String(g_lOwners, n);
        //we don't want to bother the owner if he/she is right there, so check distance
        vector vOwnerPos = (vector)llList2String(llGetObjectDetails(kAv, [OBJECT_POS]), 0);
        if (vOwnerPos == ZERO_VECTOR || llVecDist(vOwnerPos, llGetPos()) > 20.0)//vOwnerPos will be ZERO_VECTOR if not in sim
        {
            Debug("notifying " + (string)kAv);
            BigNotify(kAv, sMsg);
        }
        else
        {
            if (llSubStringIndex(sMsg, g_sOffMsg) != ERR_GENERIC && kAv != g_kWearer) Notify(kAv, sMsg, FALSE);
            Debug((string)kAv + " is right next to you! not notifying.");
        }
    }
}


SaveSetting(string sStr)
{
    list lTemp = llParseString2List(sStr, [" "], []);
    string sOption = llList2String(lTemp, 0);
    string sValue = llList2String(lTemp, 1);
    integer iIndex = llListFindList(g_lSettings, [sOption]);
    
    if(iIndex == -1)
    {
        g_lSettings += lTemp;
    }
    else
    {
        g_lSettings = llListReplaceList(g_lSettings, [sValue], iIndex + 1, iIndex + 1);
    }
    llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sScript + sOption + "=" + sValue, NULL_KEY);
    //radar, listen, trace, meters, minutes
}


EnforceSettings()
{
    integer i;
    integer iListLength = llGetListLength(g_lSettings);

    Debug("enforce settings, length: "+ (string)iListLength);
    
    for(i = 0; i < iListLength; i += 2)
    {
        string sOption = llList2String(g_lSettings, i);
        string sValue = llList2String(g_lSettings, i + 1);
        
        Debug("Option, value: "+sOption+sValue);
        
        if(sOption == "meters")
        {
            g_iSensorRange = (integer)sValue;
        }
        else if(sOption == "minutes")
        {
            g_iSensorRepeat = (integer)sValue;
        }
    }
    UpdateSensor();
    UpdateListener();
}


TurnAllOff(string command)
{ // set all values to off and remove sensor and listener
    Debug("Turn all off: " + command);
    llSensorRemove();
    llListenRemove(g_iListener);
    list lTemp;
    string sStatus;
    if ("runaway" == command) {
        g_iSensorRange = 4;
        g_iSensorRepeat = 900;
        lTemp = ["radar", "listen", "trace", "meters", "minutes"];
    } else {
        lTemp = ["radar", "listen", "trace"];
    }
    integer i;
    for (i=0; i < llGetListLength(lTemp); i++)
    {
        string sOption = llList2String(lTemp, i);
        integer iIndex = llListFindList(g_lSettings, [sOption]);
        
        if ("meters" == sOption) sStatus = (string)g_iSensorRange;
            else if ("minutes" == sOption) sStatus = (string)g_iSensorRepeat;
                else { 
                    sStatus = "off";
                }
                
        if(iIndex == -1) g_lSettings += [ sOption , sStatus];
            else {    
            g_lSettings = llListReplaceList(g_lSettings, [sStatus], iIndex + 1, iIndex + 1);
            }
        llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sScript + sOption + "=" + sStatus, NULL_KEY);
    }
    if ("safeword" == command) NotifyOwners(g_sOffMsg+" on "+g_sSubName);
    Notify(g_kWearer,g_sOffMsg,FALSE);
}


integer UserCommand(integer iNum, string sStr, key kID)
{
    Debug("UserCommand: "+ (string)iNum+" -- "+sStr);
    if (iNum < COMMAND_OWNER || iNum > COMMAND_WEARER) return FALSE;
    //only a primary owner can use this !!
    sStr = llToLower(sStr);
    if (sStr == "subspy" || sStr == "menu " + llToLower(g_sSubMenu)) DialogSpy(kID, iNum);
    else if (iNum != COMMAND_OWNER)
    { 
        if(~llListFindList(g_lCmds, [sStr]))
            Notify(kID, "Sorry, only an owner can set spy settings.", FALSE);
    }
    else // COMMAND_OWNER
    {
        Debug("UserCommand - COMMAND_OWNER");
        if (sStr == "radarsettings")//request for the radar settings menu
        {
            DialogRadarSettings(kID, iNum);
        } else if ("runaway" == sStr) TurnAllOff(sStr);
        else if (~llListFindList(g_lCmds, [sStr]))//received an actual spy command
        {
            if(sStr == "trace on")
            {
                SaveSetting(sStr);
                EnforceSettings();
                Notify(kID, "Teleport tracing is now turned on.", TRUE);
                g_sLoc=llGetRegionName();
            }
            else if(sStr == "trace off")
            {
                SaveSetting(sStr);
                EnforceSettings();
                Notify(kID, "Teleport tracing is now turned off.", TRUE);
            }
            else if(sStr == "radar on")
            {
                g_sOldAVBuffer = "";
                g_iOldAVBufferCount = -1;

                SaveSetting(sStr);
                EnforceSettings();
                Notify(kID, "Avatar radar with range of " + (string)((integer)g_iSensorRange) + "m for " + g_sSubName + " is now turned ON.", TRUE);
            }
            else if(sStr == "radar off")
            {
                SaveSetting(sStr);
                EnforceSettings();
                Notify(kID, "Avatar radar with range of " + (string)((integer)g_iSensorRange) + "m for " + g_sSubName + " is now turned OFF.", TRUE);
            }
            else if(sStr == "listen on")
            {
                SaveSetting(sStr);
                EnforceSettings();
                Notify(kID, "Chat listener enabled.", TRUE);
            }
            else if(sStr == "listen off")
            {
                SaveSetting(sStr);
                EnforceSettings();
                Notify(kID, "Chat listener disabled.", TRUE);
            }
        }
    }
    return TRUE;
}


//===============================================
//===============================================
//MAIN
//===============================================
//===============================================

default
{
    on_rez(integer iNum)
    {
        llResetScript();
    }

    state_entry()
    {
        g_kWearer = llGetOwner();
        g_sSubName = llKey2Name(g_kWearer);
        g_sLoc=llGetRegionName();
        g_lOwners = [g_kWearer, g_sSubName];  // initially self-owned until we hear a db message otherwise
        
        g_sScript = llStringTrim(llList2String(llParseString2List(llGetScriptName(), ["-"], []), 1), STRING_TRIM) + "_";
        
        llSleep(4.0);
        Notify(g_kWearer,"\n\nATTENTION: This collar is running the Spy feature.\nYour primary owners will be able to track where you go, access your radar and read what you speak in the Nearby Chat. Only your own local chat will be relayed. IMs and the chat of 3rd parties cannot be spied on. Please use an updater to uninstall this feature if you do not consent to this kind of practice and remember that bondage, power exchange and S&M is of all things based on mutual trust.",FALSE);
		Notify(g_kWearer,"\nOpenCollar SPY add-on (trace, radar, listen) INSTALLED and AVAILABLE\n...checking for activated spy features...",FALSE);
    }

    listen(integer channel, string sName, key kID, string sMessage)
    {
        if(kID == g_kWearer && channel == 0)
        {
            Debug("g_kWearer: " + sMessage);
			if(llStringLength(sMessage) > g_iReportChar) {
				sMessage = llDeleteSubString(sMessage, g_iReportChar-74, -1) +"\n***Wearer wrote too much, text discarded***";
				//Debug("was too much text: " + (string)llStringLength(sMessage));
			}
			if(llStringLength(sMessage) + llStringLength(llDumpList2String(g_lChatBuffer, "\n")) > g_iListenCap-75) {
				//Debug("too much text: "+ (string)llStringLength(sMessage)+ " - " +(string)llStringLength(llDumpList2String(g_lChatBuffer, "\n")));
				DoReports(TRUE);
			}
            if(llGetSubString(sMessage, 0, 3) == "/me ")
            {
                g_lChatBuffer += [g_sSubName + llGetSubString(sMessage, 3, -1)];
            }
            else
            {
                g_lChatBuffer += [g_sSubName + ": " + sMessage];
            }
			
			//should no longer be needed, but leaving as fallback
            //do the listencap to avoid running out of memory
            while (llStringLength(llDumpList2String(g_lChatBuffer, "\n")) > g_iListenCap)
            {
                Debug("discarding line to stay under listencap");
                g_lChatBuffer = llDeleteSubList(g_lChatBuffer, 0, 0);
            }
        }
    }

    //listen for linked messages from OC scripts
    //-----------------------------------------------
    
    link_message(integer iSender, integer iNum, string sStr, key kID)
    {
        //Debug("link_message: Sender = "+ (string)iSender + ", iNum = "+ (string)iNum + ", string = " + (string)sStr +", ID = " + (string)kID);

        if (UserCommand(iNum, sStr, kID)) return;
        else if (iNum == LM_SETTING_SAVE)
        {
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            if(sToken == "auth_owner" && llStringLength(sValue) > 0)
            {
                g_lOwners = llParseString2List(sValue, [","], []);
                Debug("owners: " + sValue);
            }
        }
        else if (iNum == LM_SETTING_RESPONSE)
        {
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            integer i = llSubStringIndex(sToken, "_");

            Debug("parse settings: "+sToken+" -- "+sValue);
            
            if(sToken == "auth_owner" && llStringLength(sValue) > 0)
            {
                g_lOwners = llParseString2List(sValue, [","], []);
                Debug("owners: " + sValue);
            }
            else if (llGetSubString(sToken, 0, i) == g_sScript)
            {
                string sOption = llToLower(llGetSubString(sToken, i+1, -1));
                Debug("got settings from db: " + sOption + sValue);
                integer iIndex = llListFindList(g_lSettings, [sOption]);
                if(iIndex == -1) g_lSettings += [ sOption , llToLower(sValue)];
                    else g_lSettings = llListReplaceList(g_lSettings, [llToLower(sValue)], iIndex + 1, iIndex + 1);
                Debug("new g_lSettings: " + (string)g_lSettings);        
                if("trace" == sOption || "radar" == sOption || "listen" == sOption) Notify(g_kWearer,"Spy add-on is ENABLED, using " + sOption + "!",FALSE);
                EnforceSettings();

                if (g_iFirstReport)
                {
                    //record initial position if trace enabled
                    if (Enabled("trace"))
                    {
                        g_lTPBuffer += ["Rezzed at " + GetLocation()];
                    }
                    g_iFirstReport = FALSE;
                }

            }
        }
        else if (iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
        {
            llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + g_sSubMenu, NULL_KEY);
        }
        else if(iNum == COMMAND_SAFEWORD)
        {//we recieved a safeword sCommand, turn all off
            TurnAllOff("safeword");
        }
        else if (iNum == DIALOG_RESPONSE)
        {
            if (kID == g_kDialogSpyID || kID == g_kDialogRadarSettingsID)
            {
                list lMenuParams = llParseString2List(sStr, ["|"], []);
                key kAv = (key)llList2String(lMenuParams, 0);
                string sMessage = llList2String(lMenuParams, 1);
                integer iPage = (integer)llList2String(lMenuParams, 2);
                integer iAuth = (integer)llList2String(lMenuParams, 3);
                if (kID == g_kDialogSpyID)
                {
                    if (sMessage == UPMENU) llMessageLinked(LINK_SET, iAuth, "menu " + g_sParentMenu, kAv);
                    else if (sMessage == "RadarSettings") DialogRadarSettings(kAv, iAuth);
                    else
                    {
                        UserCommand(iAuth, llToLower(sMessage), kAv);
                        DialogSpy(kAv, iAuth);
                    }
                }
                else if (kID == g_kDialogRadarSettingsID)
                {
                    if (sMessage == UPMENU) DialogSpy(kAv, iAuth);
                    else
                    {
                        list lTemp = llParseString2List(sMessage, [" "], []);
                        integer sValue = (integer)llList2String(lTemp,0);
                        string sOption = llList2String(lTemp,1);
                        if(sOption == "meters")
                        {
                            g_iSensorRange = sValue;
                            SaveSetting(sOption + " " + (string)sValue);
                            Notify(kAv, "Radar range changed to " + (string)((integer)sValue) + " meters.", TRUE);
                        }
                        else if(sOption == "minutes")
                        {
                            g_iSensorRepeat = sValue * 60;
                            SaveSetting(sOption + " " + (string)g_iSensorRepeat);
                            Notify(kAv, "Radar and Listen report frequency changed to " + (string)((integer)sValue) + " minutes.", TRUE);
                        }
                        if(Enabled("radar"))
                        {
                            UpdateSensor();
                        }
                        DialogRadarSettings(kAv, iAuth);
                    }
                }
            }
        }
    }

    sensor(integer iNum)
    {
        if (Enabled("radar"))
        {
            //put nearby avs in list
            integer n;
            for (n = 0; n < iNum; n++)
            {
                g_lAvBuffer += [llDetectedName(n)];
            }
        }
        else
        {
            g_lAvBuffer = [];
        }

        DoReports(FALSE);
    }

    no_sensor()
    {
        g_lAvBuffer = [];
        DoReports(FALSE);
    }

    attach(key kID)
    {
        if(kID != NULL_KEY)
        {
            g_sLoc = llGetRegionName();
        }
    }

    changed(integer iChange)
    {
        if((iChange & CHANGED_TELEPORT) || (iChange & CHANGED_REGION))
        {
            g_iOldAVBufferCount = -1;
            if(Enabled("trace"))
            {
                g_lTPBuffer += ["Teleport from " + g_sLoc + " to " +  GetLocation()+ " at " + GetTimestamp() + "."];
            }
            g_sLoc = llGetRegionName();
        }

        if (iChange & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}