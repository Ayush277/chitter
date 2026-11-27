// Shows an "ON" badge on tabs where Chitter is transcribing a call. Nothing else; no network.
chrome.runtime.onMessage.addListener((msg, sender) => {
  if (msg && msg.type === 'badge' && sender.tab) {
    chrome.action.setBadgeText({ tabId: sender.tab.id, text: msg.on ? 'ON' : '' });
    chrome.action.setBadgeBackgroundColor({ tabId: sender.tab.id, color: '#FF2BD6' });
  }
});
