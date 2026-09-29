const API = "/system/bin/sh /data/adb/modules/droidspaces-lan-ip/scripts/api.sh";
const containersEl = document.getElementById("containers");
const savedEl = document.getElementById("saved-list");
const savedSection = document.getElementById("saved-section");
const noticeEl = document.getElementById("notice");
const logEl = document.getElementById("worker-log");
const refreshEl = document.getElementById("refresh");
let callbackId = 0;
let busy = false;
let logsBusy = false;

function updateKeyboardInset() {
  const viewport = window.visualViewport;
  if (!viewport) return;
  const inset = Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop);
  document.documentElement.style.setProperty("--keyboard-inset", `${inset}px`);
}

if (window.visualViewport) {
  window.visualViewport.addEventListener("resize", updateKeyboardInset);
  window.visualViewport.addEventListener("scroll", updateKeyboardInset);
  window.addEventListener("resize", updateKeyboardInset);
  updateKeyboardInset();
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'\\''`)}'`;
}

function rootExec(command) {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== "function") {
      reject(new Error("Open this page from KernelSU Manager to manage LAN IPs."));
      return;
    }
    const callback = `droidspacesLanIpCallback${++callbackId}`;
    window[callback] = (errno, stdout, stderr) => {
      delete window[callback];
      if (errno === 0) resolve(stdout.trim());
      else reject(new Error((stderr || stdout || `Command failed (${errno})`).trim()));
    };
    try {
      window.ksu.exec(command, "{}", callback);
    } catch (error) {
      delete window[callback];
      reject(error);
    }
  });
}

function notice(message, isError = false) {
  noticeEl.textContent = message;
  noticeEl.classList.toggle("error", isError);
  noticeEl.hidden = !message;
}

function text(tag, className, value) {
  const el = document.createElement(tag);
  if (className) el.className = className;
  el.textContent = value;
  return el;
}

function parseRows(output) {
  const data = { phone: "", daemon: "waiting", containers: [], saved: [] };
  for (const line of output.split("\n")) {
    const fields = line.split("|");
    if (fields[0] === "META") {
      data.phone = fields[1] || "";
      data.daemon = fields[2] || "waiting";
    } else if (fields[0] === "CONTAINER") {
      data.containers.push({ name: fields[1], nat: fields[2], ip: fields[3], bound: fields[4], state: fields[5], extras: [] });
    } else if (fields[0] === "EXTRA") {
      const container = data.containers.find((item) => item.name === fields[1]);
      if (container) container.extras.push(fields[2]);
    } else if (fields[0] === "SAVED") {
      data.saved.push({ name: fields[1], ip: fields[2], bound: fields[3] });
    }
  }
  return data;
}

function setBusy(value) {
  busy = value;
  refreshEl.disabled = value;
  for (const button of document.querySelectorAll(".container-card button")) button.disabled = value;
}

async function mutate(command) {
  if (busy) return;
  setBusy(true);
  try {
    const message = await rootExec(command);
    await refresh(false);
    notice(message || "Saved.");
  } catch (error) {
    notice(error.message || String(error), true);
  } finally {
    setBusy(false);
  }
}

function makeCard(item, savedOnly = false) {
  const card = document.createElement("article");
  card.className = "container-card";
  const head = text("div", "card-head", "");
  const identity = document.createElement("div");
  identity.append(text("div", "container-name", item.name));
  identity.append(text("span", "subtext", savedOnly ? `Saved on ${item.bound}` : item.nat ? `Droidspaces NAT · ${item.nat}` : "Droidspaces NAT · stopped"));
  head.append(identity);
  head.append(text("span", `badge ${item.state === "active" ? "active" : ""}`, savedOnly ? "inactive" : (item.state || "pending").replaceAll("_", " ")));
  card.append(head);

  if (!savedOnly) {
    const label = text("label", "field-label", "LAN IPv4 address");
    const input = document.createElement("input");
    input.className = "ip-input";
    input.type = "text";
    input.inputMode = "decimal";
    input.autocomplete = "off";
    input.placeholder = "Address on the phone's Wi-Fi subnet";
    input.value = item.ip || "";
    input.setAttribute("aria-label", `LAN IP for ${item.name}`);
    label.append(input);
    card.append(label);
    if (item.bound) card.append(text("span", "subtext", `Saved for phone address ${item.bound}`));

    const actions = text("div", "actions", "");
    const save = text("button", "button primary", item.ip ? "Update IP" : "Assign IP");
    save.type = "button";
    save.addEventListener("click", () => {
      const ip = input.value.trim();
      if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) {
        notice("Enter an IPv4 address on the phone's Wi-Fi subnet.", true);
        return;
      }
      mutate(`${API} set ${shellQuote(item.name)} ${shellQuote(ip)}`);
    });
    actions.append(save);
    if (item.ip) actions.append(removeButton(item));
    card.append(actions);
    if (item.extras.length) {
      const extras = text("div", "extra-addresses", "");
      extras.append(text("span", "field-label", "Other proxy addresses on this container"));
      for (const ip of item.extras) {
        const row = text("div", "extra-row", "");
        row.append(text("span", "extra-ip", ip));
        const remove = text("button", "button secondary", "Remove extra IP");
        remove.type = "button";
        remove.setAttribute("aria-label", `Remove extra ${ip} from ${item.name}`);
        remove.addEventListener("click", () => mutate(`${API} delete-extra ${shellQuote(item.name)} ${shellQuote(ip)}`));
        row.append(remove);
        extras.append(row);
      }
      card.append(extras);
    }
  } else {
    card.append(text("span", "subtext", `LAN IP ${item.ip}`));
    const actions = text("div", "actions", "");
    actions.append(removeButton(item));
    card.append(actions);
  }
  return card;
}

function removeButton(item) {
  const button = text("button", "button secondary", `Remove ${item.ip}`);
  button.type = "button";
  button.setAttribute("aria-label", `Remove ${item.ip} from ${item.name}`);
  button.addEventListener("click", () => mutate(`${API} delete ${shellQuote(item.name)}`));
  return button;
}

function render(data) {
  document.getElementById("phone-address").textContent = data.phone || "No Wi-Fi IPv4 address";
  document.getElementById("daemon-status").textContent = data.daemon === "ready" ? "Droidspaces daemon is running" : "Waiting for Droidspaces daemon";
  document.getElementById("container-count").textContent = data.containers.length;
  containersEl.replaceChildren();
  if (data.containers.length) {
    for (const item of data.containers) containersEl.append(makeCard(item));
  } else {
    containersEl.append(text("p", "empty", "No NAT containers found. Set a container to NAT mode in Droidspaces first."));
  }
  savedEl.replaceChildren();
  savedSection.hidden = data.saved.length === 0;
  for (const item of data.saved) savedEl.append(makeCard(item, true));
}

async function refresh(showMessage = true) {
  try {
    const output = await rootExec(`${API} list`);
    render(parseRows(output));
    if (showMessage) notice("");
  } catch (error) {
    notice(error.message || String(error), true);
    throw error;
  }
}

async function refreshLogs() {
  if (logsBusy || document.hidden) return;
  logsBusy = true;
  const atBottom = logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight < 20;
  try {
    const output = await rootExec("if [ -f /data/adb/droidspaces-lan-ip/worker.log ]; then /system/bin/tail -n 200 /data/adb/droidspaces-lan-ip/worker.log; fi");
    logEl.textContent = output || "No activity logged yet.";
  } catch (error) {
    logEl.textContent = error.message || String(error);
  } finally {
    if (atBottom) logEl.scrollTop = logEl.scrollHeight;
    logsBusy = false;
  }
}

refreshEl.addEventListener("click", async () => {
  if (busy) return;
  setBusy(true);
  try {
    await refresh();
  } catch {
    // refresh() has already shown the error.
  } finally {
    setBusy(false);
  }
});
refresh().catch(() => {});
refreshLogs();
setInterval(refreshLogs, 5000);
