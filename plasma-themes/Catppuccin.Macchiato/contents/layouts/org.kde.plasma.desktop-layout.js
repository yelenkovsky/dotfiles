/*******Panel Top*********/
paneltop = new Panel
paneltop.hiding = "none"
paneltop.location = "top"
paneltop.floating = 1
paneltop.height = 28
paneltop.lengthMode = "fill"
/****conociendo la resolucion de pantalla*/
const width = screenGeometry(paneltop.screen).width
/**/
let localerc;
try {
    localerc = ConfigFile('plasma-localerc');
    localerc.group = "Formats";
} catch (e) {
    // Si no se puede abrir el archivo, establecer leng a "en"
    localerc = null;
}

let leng = "en"; // Valor por defecto
if (localerc) {
    let langEntry = localerc.readEntry("LANG");
    if (langEntry !== "") {
        leng = langEntry;
    }
}

let textlengu = leng.substring(0, 2);

function desktoptext(languageCode) {
    const translations = {
        "es": "Escritorio",         // Spanish
        "en": "Desktop",            // English
        "hi": "डेस्कटॉप",           // Hindi
        "fr": "Bureau",             // French
        "de": "Desktop",            // German
        "it": "Desktop",            // Italian
        "pt": "Área de trabalho",   // Portuguese
        "ru": "Рабочий стол",       // Russian
        "zh": "桌面",               // Chinese (Mandarin)
        "ja": "デスクトップ",        // Japanese
        "ko": "데스크톱",            // Korean
        "nl": "Bureaublad",         // Dutch
        "ny": "Detskyopi",          // Chichewa
        "mk": "Десктоп"             // Macedonian
    };

    // Return the translation for the language code or default to English if not found
    return translations[languageCode] || translations["en"];
}
/*kapple*/

apptitle = paneltop.addWidget("org.kde.windowtitle.Fork")
apptitle.currentConfigGroup = ["General"]
apptitle.writeConfig("customText", "true")
apptitle.writeConfig("showIcon", "false")
apptitle.writeConfig("textDefault", desktoptext(textlengu))

paneltop.addWidget("org.kde.plasma.appmenu")

paneltop.addWidget("org.kde.plasma.panelspacer")

clock = paneltop.addWidget("org.kde.plasma.digitalclock")
clock.currentConfigGroup = ["Appearance"]
clock.writeConfig("customDateFormat", "ddd d MMM")
clock.writeConfig("dateFormat", "custom")
clock.writeConfig("dateDisplayFormat", "BesideTime")
clock.writeConfig("fontStyleName", "bold")
clock.writeConfig("autoFontAndSize", "false")
clock.writeConfig("boldText", "true")
clock.writeConfig("fontWeight", 700)
clock.writeConfig("use24hFormat", "0")

paneltop.addWidget("org.kde.plasma.panelspacer")

systraprev = paneltop.addWidget("org.kde.plasma.systemtray")

controlHub = paneltop.addWidget("Plasma.Flex.Hub")
controlHub.currentConfigGroup = ["General"]
controlHub.writeConfig("elements", "19,20,10,9,2,25,8,23,21")
controlHub.writeConfig("xElements", "0,1,2,2,0,0,1,3,2")
controlHub.writeConfig("yElements", "1,1,1,2,0,3,3,3,3")
controlHub.writeConfig("selected_theme", "Custom")


/****************************/
panelbottom = new Panel
panelbottom.location = "bottom"
panelbottom.height = 51
panelbottom.offset = 0
panelbottom.floating = 1
panelbottom.alignment = "center"
panelbottom.hiding = "dodgewindows"
panelbottom.lengthMode = "fit"
panelbottom.addWidget("org.kde.plasma.marginsseparator")

menu = panelbottom.addWidget("Start.Next.Menu")
menu.currentConfigGroup = ["General"]
menu.writeConfig("customButtonImage", "slingcold")
menu.writeConfig("useCustomButtonImage", "true")

panelbottom.addWidget("org.kde.plasma.icontasks")
panelbottom.addWidget("org.kde.plasma.marginsseparator")

/*separator /*/
/*WEATHER,*/
let desktopsArray = desktopsForActivity(currentActivity());
for( var j = 0; j < desktopsArray.length; j++) {
    var desktopByClock = desktopsArray[j]
}
const marginX = Number(((screenGeometry(desktopByClock).width)-736)-24)

widget = desktopByClock.addWidget("Seeua.Weather", marginX, 48, 736, 336)
widget.currentConfigGroup = ["General"]
widget.writeConfig("colorHex", "31,29,47")

/******************************/
/*Cambiando configuracion Dolphin*/
const IconsStatic_dolphin = ConfigFile('dolphinrc')
IconsStatic_dolphin.group = 'KFileDialog Settings'
IconsStatic_dolphin.writeEntry('Places Icons Static Size', 16)
const PlacesPanel = ConfigFile('dolphinrc')
PlacesPanel.group = 'PlacesPanel'
PlacesPanel.writeEntry('IconSize', 16)
/*Buttons of aurorae*/
Buttons = ConfigFile("kwinrc")
Buttons.group = "org.kde.kdecoration2"
Buttons.writeEntry("ButtonsOnRight", "")
Buttons.writeEntry("ButtonsOnLeft", "XIA")
/******************************/
/* accent color config*/
ColorAccetFile = ConfigFile("kdeglobals")
ColorAccetFile.group = "General"
ColorAccetFile.writeEntry("accentColorFromWallpaper", "false")
ColorAccetFile.deleteEntry("AccentColor")
ColorAccetFile.deleteEntry("LastUsedCustomAccentColor")

