////////////////////////////////////////////////////////////////////////////////////
// ------------------------------------------------------------------------------ //
//                               OpenCollar - bell                                //
//                                 version 3.934                                  //
// ------------------------------------------------------------------------------ //
// Licensed under the GPLv2 with additional requirements specific to Second Life® //
// and other virtual metaverse environments.  ->  www.opencollar.at/license.html  //
// ------------------------------------------------------------------------------ //
// ©   2008 - 2013  Individual Contributors and OpenCollar - submission set free™ //
// ------------------------------------------------------------------------------ //
////////////////////////////////////////////////////////////////////////////////////

//3.927 MD: Update g_kOwners in on_rez event, as we don't necessarily reset this script and currently we may get failed permission requests targeting the wrong avatar! See line 513. Added check for runaway, if bell should be hidden, sleep for 4 seconds then re-hide the bell elements. This is to avoid other scripts resetting visibility. See line 712. Added changed event: INVENTORY changes mean more sounds may be available, so redo prepareSounds(), and LINK to redo BuildBellElementList(). See line 753

//Collar Cuff Menu

//=============================================================================
//== OC Bell Plugin - Adds bell sounds while moving to the collar, allows to adjust vol, sound and timing
//== as well to switch them off and hide the bell
//==
//== Note to Designers
//== Plugin offers option to show/hide the bell if there are prims named "Bell"
//== Plugin has a few default sounds, you can add more by putting them in the collar. The plugin scan for sounds starting with "bell_", f.i. "bell_kitty1"
//==
//== 2009-01-30 Cleo Collins - 1. draft
//==
//==
//=============================================================================

integer g_iDebugging=FALSE;

string g_sSubMenu = "Bell";
string g_sParentMenu = "AddOns";
key g_kDialogID;

list g_lLocalButtons = ["Vol +","Vol -","Delay +","Delay -"," Next Sound","  Quick Help","Ring it!"];

float g_fVolume=0.5; // volume of the bell
float g_fVolumeStep=0.1; // stepping for volume
string g_sVolToken="bellvolume"; // token for saving bell volume

float g_fSpeed=1.0; // Speed of the bell
float g_fSpeedStep=0.5; // stepping for Speed adjusting
float g_fSpeedMin=0.5; // stepping for Speed adjusting
float g_fSpeedMax=5.0; // stepping for Speed adjusting

string GLOBAL = "Global_";
string g_sSubPrefix;

integer g_iBellOn=0; // are we ringing. Off is 0, On = Auth of person which enabled
string g_sBellOn="    ON"; // menu text of bell on
string g_sBellOff="    OFF"; // menu text of bell on
integer g_iBellAvailable=FALSE;

integer g_iBellShow=TRUE; // is the bell visible
string g_sBellShow="    SHOW"; //menu text of bell visible
string g_sBellHide="   HIDE"; //menu text of bell hidden

list g_listBellSounds=["7b04c2ee-90d9-99b8-fd70-8e212a72f90d","b442e334-cb8a-c30e-bcd0-5923f2cb175a","1acaf624-1d91-a5d5-5eca-17a44945f8b0","5ef4a0e7-345f-d9d1-ae7f-70b316e73742","da186b64-db0a-bba6-8852-75805cb10008","d4110266-f923-596f-5885-aaf4d73ec8c0","5c6dd6bc-1675-c57e-0847-5144e5611ef9","1dc1e689-3fd8-13c5-b57f-3fedd06b827a"]; // list with bell sounds
key g_kCurrentBellSound ; // curent bell sound key
integer g_iCurrentBellSound; // curent bell sound sumber
integer g_iBellSoundCount; // number of avail bell sounds
string g_sBellSoundIdentifier="bell_"; // use this to find additional sounds in the inventory


string g_sBellPrimName="Bell"; // Description for Bell elements

list g_lBellElements; // list with number of prims related to the bell

float g_fNextRing; // store time for the next ringing here;

string g_sBellChatPrefix="bell"; // prefix for chat commands

key g_kWearer; // key of the current wearer to reset only on owner changes

integer g_iHasControl=FALSE; // dow we have control over the keyboard?

list g_lButtons;

//MESSAGE MAP
//integer COMMAND_NOAUTH = 0;
integer COMMAND_OWNER = 500;
integer COMMAND_SECOWNER = 501;
integer COMMAND_GROUP = 502;
integer COMMAND_WEARER = 503;
integer COMMAND_EVERYONE = 504;
integer COMMAND_RLV_RELAY = 507;

//integer SEND_IM = 1000; deprecated.  each script should send its own IMs now.  This is to reduce even the tiny bt of lag caused by having IM slave scripts
integer POPUP_HELP = 1001;

integer LM_SETTING_SAVE = 2000;//scripts send messages on this channel to have settings saved to httpdb
//str must be in form of "token=value"
integer LM_SETTING_REQUEST = 2001;//when startup, scripts send requests for settings on this channel
integer LM_SETTING_RESPONSE = 2002;//the httpdb script will send responses on this channel
integer LM_SETTING_DELETE = 2003;//delete token from DB
integer LM_SETTING_EMPTY = 2004;//sent by httpdb script when a token has no value in the db

integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer MENUNAME_REMOVE = 3003;

integer RLV_CMD = 6000;
integer RLV_REFRESH = 6001;//RLV plugins should reinstate their restrictions upon receiving this message.
integer RLV_CLEAR = 6002;//RLV plugins should clear their restriction lists upon receiving this message.

integer ANIM_START = 7000;//send this with the name of an anim in the string part of the message to play the anim
integer ANIM_STOP = 7001;//send this with the name of an anim in the string part of the message to stop the anim
integer CPLANIM_PERMREQUEST = 7002;//id should be av's key, str should be cmd name "hug", "kiss", etc
integer CPLANIM_PERMRESPONSE = 7003;//str should be "1" for got perms or "0" for not.  id should be av's key
integer CPLANIM_START = 7004;//str should be valid anim name.  id should be av
integer CPLANIM_STOP = 7005;//str should be valid anim name.  id should be av

integer DIALOG = -9000;
integer DIALOG_RESPONSE = -9001;
integer DIALOG_TIMEOUT = -9002;

string UPMENU = "BACK";//when your menu hears this, give the parent menu
string CTYPE = "collar";
string g_sScript;

key Dialog(key kRCPT, string sPrompt, list lChoices, list lUtilityButtons, integer iPage, integer iAuth)
{
    key kID = llGenerateKey();
    llMessageLinked(LINK_SET, DIALOG, (string)kRCPT + "|" + sPrompt + "|" + (string)iPage + "|" 
    + llDumpList2String(lChoices, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kID);
    return kID;
} 

string AutoPrefix()
{
    list sName = llParseString2List(llKey2Name(llGetOwner()), [" "], []);
    return llToLower(llGetSubString(llList2String(sName, 0), 0, 0)) + llToLower(llGetSubString(llList2String(sName, 1), 0, 0));
}

Notify(key kID, string sMsg, integer iAlsoNotifyWearer)
{
    if (kID == g_kWearer)
    {
        llOwnerSay(sMsg);
    }
    else
    {
        llInstantMessage(kID, sMsg);
        if (iAlsoNotifyWearer)
        {
            llOwnerSay(sMsg);
        }
    }
}
Debug(string sMsg)
{
    if (g_iDebugging)
    {
        llOwnerSay(llGetScriptName() + ": " + sMsg);
    }
}

//===============================================================================
//= parameters   :    string    sMsg    message string received
//=
//= return        :    integer TRUE/FALSE
//=
//= description  :    checks if a string begin with another string
//=
//===============================================================================

integer nStartsWith(string sHaystack, string sNeedle) // http://wiki.secondlife.com/wiki/llSubStringIndex
{
    return (llDeleteSubString(sHaystack, llStringLength(sNeedle), -1) == sNeedle);
}

//===============================================================================
//= parameters   :   key kID     ID of talking person
//=
//= return        :    none
//=
//= description  :    generate the menu for the bell
//=
//===============================================================================

DoMenu(key kID, integer iAuth)
{
    string sPrompt = "\n\n";
    // sPrompt += "(Menu will time out in " + (string)g_iTimeOut + " seconds.)\n";
    list lMyButtons = g_lLocalButtons + g_lButtons;

    //fill in your button list here

    // Show buton for ringing the bell and add a text for it
    if (g_iBellOn>0) // the bell rings currently
    {
        lMyButtons+= g_sBellOff;
        sPrompt += "Bell is ringing";
    }
    else
    {
        lMyButtons+= g_sBellOn;
        sPrompt += "Bell is NOT ringing";
    }

    // Show button for showing/hidding the bell and add a text for it, if there is a bell
    if (g_iBellAvailable)
    {
        if (g_iBellShow) // the bell is hidden
        {
            lMyButtons+= g_sBellHide;
            sPrompt += " and shown.\n\n";
        }
        else
        {
            lMyButtons+= g_sBellShow;
            sPrompt += " and NOT shown.\n\n";
        }
    }
    else
    {  // no bell, so no text or sound
        sPrompt += ".\n";
    }

    // and show the volume and timing of the bell sound
    sPrompt += "The volume of the bell is now: "+(string)((integer)(g_fVolume*10))+"/10.\n";
    sPrompt += "The bell rings every "+llGetSubString((string)g_fSpeed,0,2)+" seconds when moving.\n";
    sPrompt += "Currently used sound: "+(string)(g_iCurrentBellSound+1)+"/"+(string)g_iBellSoundCount+"\n";

    lMyButtons = llListSort(lMyButtons, 1, TRUE);

    g_kDialogID=Dialog(kID, sPrompt, lMyButtons, [UPMENU], 0, iAuth);
}

//===============================================================================
//= parameters   :   float fAlpha   alphaing for the prims
//=
//= return        :    none
//=
//= description  :    loop through stored links of prims of the bell and set the alpha for it
//=
//===============================================================================

SetBellElementAlpha(float fAlpha)
{
    //loop through stored links, setting color if element type is bell
    integer n;
    integer iLinkElements = llGetListLength(g_lBellElements);
    for (n = 0; n < iLinkElements; n++)
    {
        llSetLinkAlpha(llList2Integer(g_lBellElements,n), fAlpha, ALL_SIDES);
    }
}

//===============================================================================
//= parameters   :   none
//=
//= return        :    none
//=
//= description  :    loop throug elements and find all Bell Elements, store their prim number in a list
//=
//===============================================================================

BuildBellElementList()
{
    integer n;
    integer iLinkCount = llGetNumberOfPrims();
    list lParams;

    // clear list just in case
    g_lBellElements = [];

    //root prim is 1, so start at 2
    for (n = 2; n <= iLinkCount; n++)
    {
        // read description
        lParams=llParseString2List((string)llGetObjectDetails(llGetLinkKey(n), [OBJECT_DESC]), ["~"], []);
        // check inf name is baell name
        if (llList2String(lParams, 0)==g_sBellPrimName)
        {
            // if so store the number of the prim
            g_lBellElements += [n];
            // Debug("added " + (string)n + " to elements");
        }
    }
    if (llGetListLength(g_lBellElements)>0)
    {
        g_iBellAvailable=TRUE;
    }
    else
    {
        g_iBellAvailable=FALSE;
    }

}

//===============================================================================
//= parameters   :   none
//=
//= return        :    none
//=
//= description  :    prepare the list of bell sound, parse sounds in the collar and use when they begin with "bell_"
//=
//===============================================================================


PrepareSounds()
{
    // parse names of sounds in inventiory if those are for the bell
    integer i;
    integer m=llGetInventoryNumber(INVENTORY_SOUND);
    string s;
    for (i=0;i<m;i++)
    {
        s=llGetInventoryName(INVENTORY_SOUND,i);
        if (nStartsWith(s,g_sBellSoundIdentifier))
        {
            // sound found, add key to list
            g_listBellSounds+=llGetInventoryKey(s);
        }
    }
    // and set the current sound
    g_iBellSoundCount=llGetListLength(g_listBellSounds);
    g_iCurrentBellSound=0;
    g_kCurrentBellSound=llList2Key(g_listBellSounds,g_iCurrentBellSound);
}

//===============================================================================
//= parameters   :   keyID receiver of the help
//=
//= return        :    none
//=
//= description  :    show help for shat commands
//=
//===============================================================================


ShowHelp(key kID)
{

    string sPrompt = "\n\nHelp for bell chat command:\n";
    sPrompt += "\nAll commands for the bell of the " + CTYPE + " of "+llKey2Name(g_kWearer)+" start with \""+g_sSubPrefix+g_sBellChatPrefix+"\" followed by the command and the value, if needed.\n";
    sPrompt += "Examples: \""+g_sSubPrefix+g_sBellChatPrefix+" show\" or \""+g_sSubPrefix+g_sBellChatPrefix+" volume 10\"\n\n";
    sPrompt += "Commands:\n";
    sPrompt += "on: Enable bell sound.\n";
    sPrompt += "off: Disable bell sound.\n";
    sPrompt += "show: Show prims of bell.\n";
    sPrompt += "hide: Hide prims of bell.\n";
    sPrompt += "volume X: Set the volume for the bell, X=1-10\n";
    sPrompt += "delay X.X: Set the delay between rings, X=0.5-5.0\n";
    sPrompt += "help or ?: Show this help text.\n";

    Notify(kID,sPrompt,TRUE);

}

//===============================================================================
//= parameters   :   none
//=
//= return        :    none
//= 
//= description  :    Save settings in 1 string at the httpdb
//=
//= order of settings in the string:
//= g_iBellOn (integer),  g_iBellShow (integer), g_iCurrentBellSound (integer), g_sVolToken (integer/10), g_sSpeedToken (integer/10)
//=
//===============================================================================

SaveBellSettings()
{
    llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sScript + "on=" + (string)g_iBellOn, NULL_KEY);
    llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sScript + "show=" + (string)g_iBellShow, NULL_KEY);
    llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sScript + "sound=" + (string)g_iCurrentBellSound, NULL_KEY);
    llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sScript + "vol=" + (string)llFloor(g_fVolume*10), NULL_KEY);
    llMessageLinked(LINK_SET, LM_SETTING_SAVE, g_sScript + "speed=" + (string)llFloor(g_fSpeed*10), NULL_KEY);
}

// returns TRUE if eligible (AUTHED link message number)
integer UserCommand(integer iNum, string sStr, key kID) // here iNum: auth value, sStr: user command, kID: avatar id
{
    if (iNum > COMMAND_WEARER || iNum < COMMAND_OWNER) return FALSE; // sanity check
    string test=llToLower(sStr);
    if (sStr == "refreshmenu")
    {
        g_lButtons = [];
        llMessageLinked(LINK_SET, MENUNAME_REQUEST, g_sSubMenu, NULL_KEY);
    }
    else if (sStr == "menu " + g_sSubMenu || sStr == g_sBellChatPrefix)
    {// the command prefix + bell without any extentsion is used in chat
        //give this plugin's menu to kID
        DoMenu(kID, iNum);
    }
    // we now chekc for chat commands
    else if (nStartsWith(test,g_sBellChatPrefix))
    {
        // it is a chat commad for the bell so process it
        list lParams = llParseString2List(test, [" "], []);
        string sToken = llList2String(lParams, 1);
        string sValue = llList2String(lParams, 2);

        if (sToken=="volume")
        {
            integer n=(integer)sValue;
            if (n<1) n=1;
            if (n>10) n=10;
            g_fVolume=(float)n/10;
            SaveBellSettings();
            Notify(kID,"Bell volume set to "+(string)n, TRUE);
        }
        else if (sToken=="delay")
        {
            g_fSpeed=(float)sValue;
            if (g_fSpeed<g_fSpeedMin) g_fSpeed=g_fSpeedMin;
            if (g_fSpeed>g_fSpeedMax) g_fSpeed=g_fSpeedMax;
            SaveBellSettings();
            llWhisper(0,"Bell delay set to "+llGetSubString((string)g_fSpeed,0,2)+" seconds.");
        }
        else if (sToken=="show" || sToken=="hide")
        {
            if (sToken=="show")
            {
                g_iBellShow=TRUE;
                SetBellElementAlpha(1.0);
                Notify(kID,"The bell is now visible.",TRUE);
            }
            else
            {
                g_iBellShow=FALSE;
                SetBellElementAlpha(0.0);
                Notify(kID,"The bell is now invisible.",TRUE);
            }
            SaveBellSettings();

        }
        else if (sToken=="on")
        {
            if (iNum!=COMMAND_GROUP)
            {
                if (g_iBellOn==0)
                {
                    g_iBellOn=iNum;
                    if (!g_iHasControl)
                        llRequestPermissions(g_kWearer,PERMISSION_TAKE_CONTROLS);


                    SaveBellSettings();
                    Notify(kID,"The bell rings now.",TRUE);
                }
            }
            else
            {
                Notify(kID,"Group users or Open Acces users cannot change the ring status of the bell.",TRUE);
            }
        }
        else if (sToken=="off")
        {
            if ((g_iBellOn>0)&&(iNum!=COMMAND_GROUP))
            {
                g_iBellOn=0;

                if (g_iHasControl)
                {
                    llReleaseControls();
                    g_iHasControl=FALSE;

                }

                SaveBellSettings();
                Notify(kID,"The bell is now quiet.",TRUE);
            }
            else
            {
                Notify(kID,"Group users or Open Access users cannot change the ring status of the bell.",TRUE);
            }
        }
        else if (sToken=="nextsound")
        {
            g_iCurrentBellSound++;
            if (g_iCurrentBellSound>=g_iBellSoundCount)
            {
                g_iCurrentBellSound=0;
            }
            g_kCurrentBellSound=llList2Key(g_listBellSounds,g_iCurrentBellSound);
            Notify(kID,"Bell sound changed, now using "+(string)(g_iCurrentBellSound+1)+" of "+(string)g_iBellSoundCount+".",TRUE);
        }
        // show the help
        else if (sToken=="help" || sToken=="?")
        {
            ShowHelp(kID);
        }
        // let the bell ring one time
        else if (sToken=="ring")
        {
            // update variable for time check
            g_fNextRing=llGetTime()+g_fSpeed;
            // and play the sound
            llPlaySound(g_kCurrentBellSound,g_fVolume);
        }

    }
    return TRUE;
}

default
{
    state_entry()
    {
        g_sScript = llStringTrim(llList2String(llParseString2List(llGetScriptName(), ["-"], []), 1), STRING_TRIM) + "_";
        // key of the owner
        g_kWearer=llGetOwner();
        g_sSubPrefix=AutoPrefix();

        // reset script time used for ringing the bell in intervalls
        llResetTime();

        // bild up list of prims with bell elements
        BuildBellElementList();

        PrepareSounds();
        //not needed anymore as we request menus already
        // now wait  to be sure al other scripts reseted and init the menu system into the collar
        //llSleep(1.0);
        //llMessageLinked(LINK_SET, MENUNAME_REQUEST, g_sSubMenu, NULL_KEY);
        //llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + g_sSubMenu, NULL_KEY);

    }
    on_rez(integer param)
    {
        g_kWearer=llGetOwner();
        g_sSubPrefix=AutoPrefix();
    }
    link_message(integer iSender, integer iNum, string sStr, key kID)
    {
        if (iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
        {
            // the menu structure is to be build again, so make sure we get recognized
            llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + g_sSubMenu, NULL_KEY);
        }
        else if (iNum == MENUNAME_RESPONSE)
        {
            list lParts = llParseString2List(sStr, ["|"], []);
            if (llList2String(lParts, 0) == g_sSubMenu)
            {//someone wants to stick something in our menu
                string button = llList2String(lParts, 1);
                if (llListFindList(g_lButtons, [button]) == -1)
                {
                    g_lButtons = llListSort(g_lButtons + [button], 1, TRUE);
                }
            }
        }
        else if (iNum == LM_SETTING_RESPONSE)
        {
            // some responses from the DB are coming in, check if it is about bell values
            integer i = llSubStringIndex(sStr, "=");
            string sToken = llGetSubString(sStr, 0, i - 1);
            string sValue = llGetSubString(sStr, i + 1, -1);
            i = llSubStringIndex(sToken, "_");
            if (llGetSubString(sToken, 0, i) == g_sScript)
            {
                sToken = llGetSubString(sToken, i + 1, -1);
                if (sToken == "on")
                {
                    g_iBellOn=(integer)sValue;
                    if (g_iBellOn & !g_iHasControl)
                    {
                        llRequestPermissions(g_kWearer,PERMISSION_TAKE_CONTROLS);
                    }
                    else if (!g_iBellOn & g_iHasControl)
                    {
                        llReleaseControls();
                        g_iHasControl=FALSE;
                    }
                }
                else if (sToken == "show")
                {
                    g_iBellShow=(integer)sValue;
                    if (g_iBellShow) SetBellElementAlpha(1.0);
                    else SetBellElementAlpha(0.0);
                }
                else if (sToken == "sound")
                {
                    g_iCurrentBellSound=(integer)sValue;
                    g_kCurrentBellSound=llList2Key(g_listBellSounds,g_iCurrentBellSound);
                }
                else if (sToken == "vol") g_fVolume=(float)sValue/10;
                else if (sToken == "speed") g_fSpeed=(float)sValue/10;
            }
            else if (sToken == "Global_prefix") g_sSubPrefix=sValue;
            else if (sToken == "Global_CType") CTYPE = sValue;
        }
        else if (iNum == LM_SETTING_SAVE)
        {
            integer i = llSubStringIndex(sStr, "=");
            string sToken = llGetSubString(sStr, 0, i - 1);
            string sValue = llGetSubString(sStr, i + 1, -1);
            if (sToken == "Global_prefix") g_sSubPrefix=sValue;
        }
        else if (UserCommand(iNum, sStr, kID)) return;
        else if (iNum==DIALOG_RESPONSE)
        {
            //str will be a 2-element, pipe-delimited list in form pagenum|response
    
            if (kID == g_kDialogID)
            {
                list lMenuParams = llParseString2List(sStr, ["|"], []);
                key kAV = llList2String(lMenuParams, 0);
                string sMessage = llList2String(lMenuParams, 1);
                integer iPage = (integer)llList2String(lMenuParams, 2);
                integer iAuth = (integer)llList2String(lMenuParams, 3);
                if (sMessage == UPMENU)
                {
                    //give id the parent menu
                    llMessageLinked(LINK_SET, iAuth, "menu "+g_sParentMenu, kAV);
                    return; // no "remenu"
                }
                else if (~llListFindList(g_lLocalButtons, [sMessage]))
                {
                    //we got a response for something we handle locally
                    if (sMessage == "Vol +")
                        // pump up the volume and store the value
                    {
                        g_fVolume+=g_fVolumeStep;
                        if (g_fVolume>1.0)
                        {
                            g_fVolume=1.0;
                        }
                        SaveBellSettings();
                    }
                    else if (sMessage == "Vol -")
                        // be more quiet, and store the value
                    {
                        g_fVolume-=g_fVolumeStep;
                        if (g_fVolume<0.1)
                        {
                            g_fVolume=0.1;
                        }
                        SaveBellSettings();
                    }
                    else if (sMessage == "Delay +")
                        // dont annoy people and ring slower
                    {
                        g_fSpeed+=g_fSpeedStep;
                        if (g_fSpeed>g_fSpeedMax)
                        {
                            g_fSpeed=g_fSpeedMax;
                        }
                        SaveBellSettings();
                    }
                    else if (sMessage == "Delay -")
                        // annoy the hell out of the, ring plenty, ring often
                    {
                        g_fSpeed-=g_fSpeedStep;
                        if (g_fSpeed<g_fSpeedMin)
                        {
                            g_fSpeed=g_fSpeedMin;
                        }
                        SaveBellSettings();
                    }
                    else if (sMessage == " Next Sound")
                        // choose another sound for the bell
                    {
                        g_iCurrentBellSound++;
                        if (g_iCurrentBellSound>=g_iBellSoundCount)
                        {
                            g_iCurrentBellSound=0;
                        }
                        g_kCurrentBellSound=llList2Key(g_listBellSounds,g_iCurrentBellSound);

                        SaveBellSettings();
                    }
                    // show help
                    else if (sMessage=="  Quick Help")
                    {
                        ShowHelp(kAV);
                    }
                    //added a button to ring the bell. same call as when walking.
                    else if (sMessage == "Ring it!")
                    {
                        // update variable for time check
                        g_fNextRing=llGetTime()+g_fSpeed;
                        // and play the sound
                        llPlaySound(g_kCurrentBellSound,g_fVolume);
                        //Debug("Bing");
                    }

                }
                else if (sMessage == g_sBellOff || sMessage == g_sBellOn)
                    // someone wants to change ioif the bell rings or not
                {
                    string s;
                    if (g_iBellOn>0)
                    {
                        s="bell off";
                    }
                    else
                    {
                        s="bell on";
                    }
                    UserCommand(iAuth,s,kAV);
                }
                else if (sMessage == g_sBellShow || sMessage == g_sBellHide)
                    // someone wants to hide or show the bell
                {
                    g_iBellShow=!g_iBellShow;
                    if (g_iBellShow)
                    {
                        SetBellElementAlpha(1.0);
                    }
                    else
                    {
                        SetBellElementAlpha(0.0);
                    }
                    SaveBellSettings();
                }
                else if (~llListFindList(g_lButtons, [sMessage]))
                {
                    //we got a submenu selection
                    UserCommand(iAuth, "menu "+sMessage, kAV);
                    return; // no main menu
                }
                // do we want to see the menu again?
                DoMenu(kAV, iAuth);

            }
        }
        else if(iNum=COMMAND_OWNER && sStr=="runaway")
        {
            if (!g_iBellShow)
            {
                llSleep(4);
                SetBellElementAlpha(0.0);
            }
        }
    }

    control( key kID, integer nHeld, integer nChange )
        // we watch for movement from
    {
        // we dont want the bell to ring, so just exit
        if (!g_iBellOn) return;
        // Is the user holding down a movement key
        if ( nHeld & (CONTROL_LEFT|CONTROL_RIGHT|CONTROL_DOWN|CONTROL_UP|CONTROL_ROT_LEFT|CONTROL_ROT_RIGHT|CONTROL_FWD|CONTROL_BACK) )
        {
            // check if the time is ready for the next ring
            if (llGetTime()>g_fNextRing)
            {
                // update variable for time check
                g_fNextRing=llGetTime()+g_fSpeed;
                // and play the sound
                llPlaySound(g_kCurrentBellSound,g_fVolume);
                //Debug("Bing");
            }
        }
    }

    run_time_permissions(integer nParam)
        // we requested permissions, now we take control
    {
        if( nParam & PERMISSION_TAKE_CONTROLS)
        {
            //Debug("Bing");
            llTakeControls( CONTROL_DOWN|CONTROL_UP|CONTROL_FWD|CONTROL_BACK|CONTROL_LEFT|CONTROL_RIGHT|CONTROL_ROT_LEFT|CONTROL_ROT_RIGHT, TRUE, TRUE);
            g_iHasControl=TRUE;

        }
    }
    changed(integer change)
    {
        if(change & CHANGED_LINK) BuildBellElementList();
        else if (change & CHANGED_INVENTORY) PrepareSounds();
    }

}
