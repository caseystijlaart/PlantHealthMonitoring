const KEY = 'pof03_profiles';

const els = {
  apiBase: document.getElementById('apiBase'),
  loadBtn: document.getElementById('loadBtn'),
  plantForm: document.getElementById('plantForm'),
  submitResult: document.getElementById('submitResult'),
  profileList: document.getElementById('profileList'),
};

const readProfiles = () => JSON.parse(localStorage.getItem(KEY) || '[]');
const saveProfiles = (profiles) => localStorage.setItem(KEY, JSON.stringify(profiles));

const baseUrl = () => (els.apiBase.value || '').replace(/\/$/, '');

function renderProfiles() {
  const profiles = readProfiles();
  els.profileList.innerHTML = '';

  if (!profiles.length) {
    els.profileList.innerHTML = '<li>No profiles created yet.</li>';
    return;
  }

  profiles.forEach((p) => {
    const li = document.createElement('li');
    li.textContent = `${p.plantName} | humidity:${p.humidityPreference}, temperature:${p.temperaturePreference}, soil:${p.soilPreference}, light:${p.lightPreference}`;
    els.profileList.appendChild(li);
  });
}

async function loadSettings() {
  const base = baseUrl();
  if (!base) {
    els.submitResult.textContent = 'Provide ESP32 API base URL first.';
    els.submitResult.className = 'error';
    return;
  }

  try {
    const res = await fetch(`${base}/api/plant-settings`);
    const data = await res.json();
    els.plantForm.plantName.value = data.plantName || '';
    els.plantForm.humidityPreference.value = data.humidityPreference || 'pMid';
    els.plantForm.temperaturePreference.value = data.temperaturePreference || 'pMid';
    els.plantForm.soilPreference.value = data.soilPreference || 'pMid';
    els.plantForm.lightPreference.value = data.lightPreference || 'pMid';
    els.submitResult.textContent = 'Loaded settings from ESP32.';
    els.submitResult.className = 'success';
  } catch (err) {
    els.submitResult.textContent = `Could not load settings: ${err.message}`;
    els.submitResult.className = 'error';
  }
}

async function submitProfile(event) {
  event.preventDefault();
  const base = baseUrl();
  if (!base) {
    els.submitResult.textContent = 'Provide ESP32 API base URL first.';
    els.submitResult.className = 'error';
    return;
  }

  const formData = new FormData(els.plantForm);
  const values = Object.fromEntries(formData.entries());

  try {
    const response = await fetch(`${base}/api/plant-settings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(values),
    });
    const text = await response.text();

    const profiles = readProfiles();
    profiles.push(values);
    saveProfiles(profiles);
    renderProfiles();

    els.submitResult.textContent = text;
    els.submitResult.className = response.ok ? 'success' : 'error';

    loadSettings();
  } catch (err) {
    els.submitResult.textContent = `Could not save settings: ${err.message}`;
    els.submitResult.className = 'error';
  }
}

els.loadBtn.addEventListener('click', loadSettings);
els.plantForm.addEventListener('submit', submitProfile);
renderProfiles();
