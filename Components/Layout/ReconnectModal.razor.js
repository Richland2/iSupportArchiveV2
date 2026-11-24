// "Rejoining the server..." when the page loses its connection to the app (a restart, a deploy, sleep, a network
// blip). Changed from .NET's version so people rarely see it and never have to reload by hand:
// - it only shows once the connection has been down for a couple of seconds, so blips pass unnoticed;
// - after Blazor's own attempts give up, it keeps trying every few seconds (and when the tab is shown again);
// - when the app is back but no longer has this page's session (it restarted), the page reloads by itself.
const showAfterMs = 2000;
const retryEveryMs = 5000;

const reconnectModal = document.getElementById("components-reconnect-modal");
reconnectModal.addEventListener("components-reconnect-state-changed", handleReconnectStateChanged);

const retryButton = document.getElementById("components-reconnect-button");
retryButton.addEventListener("click", retry);

const resumeButton = document.getElementById("components-resume-button");
resumeButton.addEventListener("click", resume);

let showTimer, retryTimer;

function handleReconnectStateChanged(event) {
    if (event.detail.state === "show") {
        clearTimeout(showTimer);
        showTimer = setTimeout(() => reconnectModal.showModal(), showAfterMs);
    } else if (event.detail.state === "hide") {
        stopRetrying();
        clearTimeout(showTimer);
        reconnectModal.close();
    } else if (event.detail.state === "failed") {
        keepRetrying();
    } else if (event.detail.state === "rejected") {
        location.reload();
    }
}

function keepRetrying() {
    document.addEventListener("visibilitychange", retryWhenDocumentBecomesVisible);
    clearTimeout(retryTimer);
    retryTimer = setTimeout(retry, retryEveryMs);
}

function stopRetrying() {
    document.removeEventListener("visibilitychange", retryWhenDocumentBecomesVisible);
    clearTimeout(retryTimer);
}

async function retry() {
    stopRetrying();

    try {
        // Reconnect will asynchronously return:
        // - true to mean success
        // - false to mean we reached the server, but it rejected the connection (e.g., unknown circuit ID)
        // - exception to mean we didn't reach the server (this can be sync or async)
        const successful = await Blazor.reconnect();
        if (!successful) {
            // The app is back but this page's session is gone: try to resume it, otherwise reload the page.
            const resumeSuccessful = await Blazor.resumeCircuit();
            if (!resumeSuccessful) {
                location.reload();
            } else {
                reconnectModal.close();
            }
        }
    } catch (err) {
        // The app can't be reached yet: try again shortly
        keepRetrying();
    }
}

async function resume() {
    try {
        const successful = await Blazor.resumeCircuit();
        if (!successful) {
            location.reload();
        }
    } catch {
        reconnectModal.classList.replace("components-reconnect-paused", "components-reconnect-resume-failed");
    }
}

async function retryWhenDocumentBecomesVisible() {
    if (document.visibilityState === "visible") {
        await retry();
    }
}
