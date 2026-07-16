const screenMid = 0;
const screenMac = 1;
const screenVertical = 2;

const locFull = 0;
const locTopHalf = 1;
const locBottomHalf = 2;
const locLeftHalf = 3;
const locRightHalf = 4;
const locTopLeft = 5;
const locTopRight = 6;
const locBottomLeft = 7;
const locBottomRight = 8;

const keyWindowsHidden = "keyWindowsHidden";

// Key to store which Rider app was last focused
const keyLastRider = "keyLastRider";

const moveApp = (appTitle, screenIndex, targetLocation) => {
    const app = getApp(appTitle);
    if (!app) return; // Exit if app is not running

    const window = app.mainWindow();
    if (!window) return; // Exit if there's no main window for app

    // Get screen information
    const screens = Screen.all();
    let targetScreen;
    if (screens.length < 3) { // custom setup for the office
        targetScreen = screens[0]
    } else {
        targetScreen = screens[screenIndex]
    }
    const screenFrame = targetScreen.flippedVisibleFrame();
    let targetFrame;

    switch (targetLocation) {
    case locFull:
        // full screen
        targetFrame = screenFrame;
        break;
    case locTopHalf:
        targetFrame = {
            x: screenFrame.x,
            y: screenFrame.y,
            width: screenFrame.width,
            height: screenFrame.height / 2,
        };
        break;
    case locBottomHalf:
        targetFrame = {
            x: screenFrame.x,
            y: screenFrame.y + screenFrame.height / 2,
            width: screenFrame.width,
            height: screenFrame.height / 2,
        };
        break;
    case locLeftHalf:
        targetFrame = {
            x: screenFrame.x,
            y: screenFrame.y,
            width: screenFrame.width / 2,
            height: screenFrame.height,
        };
        break;
    case locRightHalf:
        targetFrame = {
            x: screenFrame.x + screenFrame.width / 2,
            y: screenFrame.y,
            width: screenFrame.width / 2,
            height: screenFrame.height,
        };
        break;
    case locTopLeft:
        targetFrame = {
            x: screenFrame.x,
            y: screenFrame.y,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2,
        };
        break;
    case locTopRight:
        targetFrame = {
            x: screenFrame.x + screenFrame.width / 2,
            y: screenFrame.y,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2,
        };
        break;
    case locBottomLeft:
        targetFrame = {
            x: screenFrame.x,
            y: screenFrame.y + screenFrame.height / 2,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2,
        };
        break;
    case locBottomRight:
        targetFrame = {
            x: screenFrame.x + screenFrame.width / 2,
            y: screenFrame.y + screenFrame.height / 2,
            width: screenFrame.width / 2,
            height: screenFrame.height / 2,
        };
        break;
    default:
        break;
    }

    // Move and resize the window
    window.setFrame(targetFrame);
    app.show();
    return app;
}

const getApp = (str) => {
    let app = App.get(str);
    if (!app) { // fallback to bundle identifier if app is not found (fix for whatsapp)
        const apps = App.all();
        for (const a of apps) {
            const bundleIdentifier = a.bundleIdentifier();
            if (bundleIdentifier === str) {
                return a;
            }
        }
    }
    return app;
}

const hideApp = (appTitle) => {
    const app = getApp(appTitle);
    if (!app) return; // Exit if app is not running
    app.hide();
    return app;
}

const showApp = (appTitle) => {
    const app = getApp(appTitle);
    if (!app) return; // Exit if app is not running
    app.show();
    return app;
}

const focusApp = (appTitle) => {
    const app = getApp(appTitle);
    if (!app) return; // Exit if app is not running
    const window = app.mainWindow();
    if (!app.isActive()) {
        app.show();
        app.focus();
    }
    return app;
}

const toggleApp = (appTitle) => {
    const app = getApp(appTitle);
    if (!app) return; // Exit if app is not running
    const window = app.mainWindow();
    if (window && window.isVisible()) {
        app.hide();
    } else if (window && !window.isVisible()) {
        app.show();
        app.focus();
    }
}

const toggleAllWindows = () => {
    let areWindowsHidden = Storage.get(keyWindowsHidden);
    if (areWindowsHidden === undefined) {
        // if there is no key, assume windows are not hidden
        areWindowsHidden = false;
        Storage.set(keyWindowsHidden, areWindowsHidden);
    }

    const windows = Window.all();
    if (windows.length === 0) return;

    // toggle
    if (areWindowsHidden) {
        // show all windows
        console.log("showing all windows");
        windows.forEach(window => {
            window.unminimise();
        })
        Storage.set(keyWindowsHidden, false);
    } else {
        // hide all windows
        console.log("hiding all windows");
        windows.forEach(window => {
            window.minimise();
        })
        Storage.set(keyWindowsHidden, true);
    }
}

const modeSocial = () => {
    showApp('net.whatsapp.WhatsApp');
    moveApp('net.whatsapp.WhatsApp', screenMac, locBottomRight);
    const focusedApp = showApp('Telegram');
    moveApp('Telegram', screenMac, locTopRight);
    if (focusedApp) focusedApp.focus();
}

const modePrivate = () => {
    hideApp('Telegram');
    hideApp('net.whatsapp.WhatsApp');
}

const modeWork = () => {
    moveApp('Spotify', screenVertical, locTopHalf);
    moveApp('Slack', screenMac, locLeftHalf);
    moveApp('Sublime Text', screenVertical, locBottomHalf);
    const focusedApp = moveApp('Google Chrome', screenMid, locFull);
    if (focusedApp) focusedApp.focus();
}

const debug = () => {
    // open logs in terminal:
    // log stream --process Phoenix
    console.log('*** DEBUG ***');
    const apps = App.all();
    for (const app of apps) {
        const appName = app.name();
        console.log(appName);
        const appBundleIdentifier = app.bundleIdentifier();
        console.log(appBundleIdentifier);
    }
    console.log('*** OVER ***');
}

const whatsapp = () => {
    toggleApp('net.whatsapp.WhatsApp');
}

const telegram = () => {
    toggleApp('Telegram');
}

const slack = () => {
    toggleApp('Slack');
}

const spotify = () => {
    toggleApp('Spotify');
}

const chrome = () => {
    focusApp('Google Chrome')
}

const lmstudio = () => {
    toggleApp('LM Studio')
}

const photobooth = () => {
    const appName = "Photo Booth";
    const app = getApp(appName);
    if (!app) App.launch(appName);
    toggleApp(appName);
}

const sourcetree = () => {
    focusApp('Sourcetree');
}

const rider = () => {
    focusApp('com.jetbrains.rider');
}

// Toggle between the two Rider apps (cypher-backend-core and cypher-admin-dashboard)
// First press opens Rider-cbc, second press opens Rider-cad, third press back to cbc, etc
// Rider-cbc and Rider-cad have been created as Automator launcher apps that open
// cypher-backend-core and cypher-admin-dashboard projects respectively in Rider
const toggleRider = () => {
    const lastRider = Storage.get(keyLastRider) || 'Rider-cad';

    if (lastRider === 'Rider-cbc') {
        App.launch('Rider-cad');
        Storage.set(keyLastRider, 'Rider-cad');
    } else {
        App.launch('Rider-cbc');
        Storage.set(keyLastRider, 'Rider-cbc');
    }
}

const identifier = Event.on('didLaunch', (app) => {
  console.log("BOOTING");
  Storage.set(keyWindowsHidden, false);
});

// ** DEBUG **
// Uncomment, reload phoenix, and open logs in terminal with: log stream --process Phoenix
// Key.on('n', ['control', 'command'], debug);

Key.on('j', ['control', 'command'], modeWork);
Key.on('k', ['control', 'command'], modeSocial);
Key.on('l', ['control', 'command'], modePrivate);

Key.on('h', ['control', 'command'], toggleAllWindows);

Key.on('w', ['control', 'command'], whatsapp);
Key.on('t', ['control', 'command'], telegram);
Key.on('a', ['control', 'command'], slack);
Key.on('s', ['control', 'command'], spotify);
Key.on('y', ['control', 'command'], chrome);
Key.on('r', ['control', 'command'], photobooth);

Key.on('\;', ['control', 'command'], sourcetree);

// Key.on(']', ['control', 'command'], rider);
Key.on('\'', ['control', 'command'], toggleRider);

// my thor launcher shortcuts
// Finder: ctrl cmd e
// Sublime Text: ctrl cmd p
// massCode: ctrl cmd M

// my macOS shortcuts
// Chrome (Personal): ctrl cmd u
// Chrome (Work): ctrl cmd i

