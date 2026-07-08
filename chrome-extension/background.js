const NATIVE_HOST = 'com.local.livewallpaper';

// content script / popup からのコマンドを Native Messaging host へ中継する
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.kind !== 'wallpaper-command' || !message.command) {
    return false;
  }
  chrome.runtime.sendNativeMessage(NATIVE_HOST, message.command, (response) => {
    if (chrome.runtime.lastError) {
      sendResponse({ ok: false, error: chrome.runtime.lastError.message });
      return;
    }
    sendResponse(response ?? { ok: true });
  });
  return true; // 非同期で sendResponse する
});
