const statusEl = document.getElementById('status');

function showStatus(text) {
  statusEl.textContent = text;
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

async function sendAndReport(command, doneText) {
  const response = await sendCommand(command);
  showStatus(response.ok ? doneText : `失敗: ${response.error ?? '不明なエラー'}`);
}

document.getElementById('play-current').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url || !tab.url.includes('youtube.com')) {
    showStatus('YouTube のタブを開いてください');
    return;
  }
  // content script に playlist 抽出込みで収集してもらう。届かなければ URL のみで送る
  chrome.tabs.sendMessage(tab.id, { kind: 'collect-wallpaper-target' }, async (collected) => {
    const command = (!chrome.runtime.lastError && collected)
      ? collected
      : { type: 'play', url: tab.url, videoIds: [] };
    await sendAndReport(command, '壁紙にしました');
  });
});

document.getElementById('off').addEventListener('click', () => {
  sendAndReport({ type: 'off' }, '通常壁紙に戻しました');
});

document.getElementById('toggle').addEventListener('click', () => {
  sendAndReport({ type: 'pause' }, '再生 / 一時停止');
});

document.getElementById('previous').addEventListener('click', () => {
  sendAndReport({ type: 'previous' }, '前の動画へ');
});

document.getElementById('next').addEventListener('click', () => {
  sendAndReport({ type: 'next' }, '次の動画へ');
});

const volumeSlider = document.getElementById('volume');
let volumeTimer = null;
volumeSlider.addEventListener('input', () => {
  // sendNativeMessage はメッセージごとにプロセスを起動するので間引く
  clearTimeout(volumeTimer);
  volumeTimer = setTimeout(() => {
    const value = Number(volumeSlider.value);
    chrome.storage.local.set({ volume: value });
    sendAndReport({ type: 'volume', value }, `音量 ${value}`);
  }, 150);
});

document.getElementById('seek').addEventListener('change', (event) => {
  const percent = Number(event.target.value) / 1000;
  sendAndReport({ type: 'seek', percent }, `シーク ${(percent * 100).toFixed(0)}%`);
});

const subtitlesCheckbox = document.getElementById('subtitles');
subtitlesCheckbox.addEventListener('change', () => {
  const enabled = subtitlesCheckbox.checked;
  chrome.storage.local.set({ subtitles: enabled });
  sendAndReport({ type: 'subtitles', enabled }, enabled ? '字幕オン' : '字幕オフ');
});

const largestOnlyCheckbox = document.getElementById('largest-only');
largestOnlyCheckbox.addEventListener('change', () => {
  const largestOnly = largestOnlyCheckbox.checked;
  sendAndReport(
    { type: 'screens', largestOnly },
    largestOnly ? '最大モニターのみ表示' : '全モニターに表示'
  );
});

const qualitySelect = document.getElementById('quality');
qualitySelect.addEventListener('change', () => {
  sendAndReport({ type: 'quality', value: qualitySelect.value }, `画質上限 ${qualitySelect.options[qualitySelect.selectedIndex].text}`);
});

// native 側の実状態(設定ファイル + state.json)で UI を初期化する。
// native host に届かない時だけ storage の前回値にフォールバック
async function syncStatus() {
  const status = await sendCommand({ type: 'status' });
  if (!status.ok) {
    chrome.storage.local.get({ volume: 0, subtitles: false }, ({ volume, subtitles }) => {
      volumeSlider.value = String(volume);
      subtitlesCheckbox.checked = subtitles;
    });
    showStatus('native host に接続できません');
    return;
  }
  if (typeof status.volume === 'number') {
    volumeSlider.value = String(status.volume);
  }
  largestOnlyCheckbox.checked = Boolean(status.largestOnly);
  if (status.quality) {
    qualitySelect.value = status.quality;
  }
  if (typeof status.progress === 'number') {
    document.getElementById('seek').value = String(Math.round(status.progress * 1000));
  }
  chrome.storage.local.get({ subtitles: false }, ({ subtitles }) => {
    subtitlesCheckbox.checked = subtitles;
  });
  if (!status.appRunning) {
    showStatus('壁紙アプリは未起動です');
  } else if (status.url) {
    showStatus(`${status.playing ? '再生中' : '停止中'}: ${status.url}`);
  }
}

syncStatus();
