// YouTube ページに「壁紙にする」ボタンを表示し、現在の動画/playlist を native 側へ送る

const BUTTON_ID = 'codex-wallpaper-button';

function extractVideoID(href) {
  try {
    const url = new URL(href, location.origin);
    const v = url.searchParams.get('v');
    if (v) return v;
    if (url.hostname === 'youtu.be') {
      return url.pathname.split('/').filter(Boolean)[0] || null;
    }
  } catch {
    return null;
  }
  return null;
}

// ログイン済み Chrome 上で見えている playlist item から動画 ID 一覧を拾う
function collectPlaylistVideoIDs() {
  const selectors = [
    // watch ページ右側の playlist パネル
    'ytd-playlist-panel-video-renderer a#wc-endpoint',
    // /playlist ページの一覧
    'ytd-playlist-video-renderer a#video-title',
  ];
  const ids = [];
  for (const selector of selectors) {
    for (const anchor of document.querySelectorAll(selector)) {
      const id = extractVideoID(anchor.href);
      if (id && !ids.includes(id)) {
        ids.push(id);
      }
    }
  }
  return ids;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// playlist は lazy load されるので、スクロールして全件 DOM に載せてから収集する
async function loadAllPlaylistItems() {
  const panel = document.querySelector('ytd-playlist-panel-renderer #items');
  const isPlaylistPage = location.pathname === '/playlist';
  if (!panel && !isPlaylistPage) {
    return;
  }
  const originalPanelScroll = panel?.scrollTop ?? 0;
  const originalPageScroll = window.scrollY;
  let lastCount = -1;
  for (let i = 0; i < 20; i++) {
    const count = collectPlaylistVideoIDs().length;
    if (count === lastCount) {
      break;
    }
    lastCount = count;
    if (panel) {
      panel.scrollTop = panel.scrollHeight;
    }
    if (isPlaylistPage) {
      window.scrollTo(0, document.documentElement.scrollHeight);
    }
    await sleep(400);
  }
  if (panel) {
    panel.scrollTop = originalPanelScroll;
  }
  if (isPlaylistPage) {
    window.scrollTo(0, originalPageScroll);
  }
}

async function collect() {
  await loadAllPlaylistItems();
  const videoIds = collectPlaylistVideoIDs();
  const currentId = extractVideoID(location.href);
  // 現在再生中の動画から始まるよう並べ替える
  if (currentId && videoIds.includes(currentId)) {
    const index = videoIds.indexOf(currentId);
    videoIds.push(...videoIds.splice(0, index));
  }
  return { type: 'play', url: location.href, videoIds };
}

function sendCommand(command) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage({ kind: 'wallpaper-command', command }, (response) => {
      if (chrome.runtime.lastError) {
        resolve({ ok: false, error: chrome.runtime.lastError.message });
        return;
      }
      resolve(response ?? { ok: false, error: 'no response' });
    });
  });
}

function isTargetPage() {
  return location.pathname === '/watch' || location.pathname === '/playlist';
}

function updateButton() {
  let button = document.getElementById(BUTTON_ID);
  if (!isTargetPage()) {
    button?.remove();
    return;
  }
  if (button) {
    return;
  }
  button = document.createElement('button');
  button.id = BUTTON_ID;
  button.textContent = '🖥 壁紙にする';
  Object.assign(button.style, {
    position: 'fixed',
    right: '16px',
    bottom: '16px',
    zIndex: '9999',
    padding: '8px 14px',
    borderRadius: '18px',
    border: 'none',
    background: 'rgba(0, 0, 0, 0.75)',
    color: '#fff',
    font: '500 13px/1.4 -apple-system, sans-serif',
    cursor: 'pointer',
    boxShadow: '0 2px 8px rgba(0, 0, 0, 0.4)',
  });
  button.addEventListener('click', async () => {
    button.textContent = '⏳ 送信中…';
    const response = await sendCommand(await collect());
    button.textContent = response.ok ? '✅ 壁紙にしました' : '⚠️ 失敗しました';
    setTimeout(() => {
      button.textContent = '🖥 壁紙にする';
    }, 2500);
  });
  document.body.appendChild(button);
}

// popup からの playlist 収集リクエストに応える(スクロール収集があるので非同期)
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message && message.kind === 'collect-wallpaper-target') {
    collect().then(sendResponse);
    return true;
  }
  return false;
});

// YouTube は SPA なのでナビゲーション完了イベントでもボタンを更新する
document.addEventListener('yt-navigate-finish', updateButton);
updateButton();
