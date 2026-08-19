#!/usr/bin/env python3
"""Deploy FPI website AI disclaimer + chatbot. Run as root."""
from pathlib import Path
from datetime import datetime
import os
import subprocess

base = Path("/var/www/firstpropertyinvestment.us")
ts = datetime.now().strftime("%Y%m%d-%H%M")

for name in ("index.html", "send.php"):
    src = base / name
    bak = base / f"{name}.bak-{ts}"
    bak.write_bytes(src.read_bytes())
    print("backed up", bak)

html = (base / "index.html").read_text(encoding="utf-8", errors="replace")
if "<!DOCTYPE html>" in html:
    html = html[html.index("<!DOCTYPE html>") :]

disclaimer = """
                    <div class="mb-4 p-3 bg-gray-100 rounded-md text-sm text-gray-800">
                        <p class="font-semibold mb-1">AI assistant disclosure</p>
                        <p class="mb-2">First Property Investment uses an AI phone agent (<strong>Alex</strong>) to return calls, answer basic questions, and schedule next steps. You can request a human at any time.</p>
                        <label class="flex items-start gap-2 cursor-pointer">
                            <input type="checkbox" name="ai_call_consent" id="ai_call_consent" value="yes" class="mt-1" required>
                            <span>I agree that an <strong>AI agent from First Property Investment</strong> may call or text me about selling my property. I understand this is an automated assistant, not a live person on every call.</span>
                        </label>
                    </div>
                    <div class="mb-4">
                        <label for="call_preference" class="block text-sm font-medium">When can Alex call?</label>
                        <select id="call_preference" name="call_preference" class="w-full p-2 border rounded-md" required>
                            <option value="short_call_now">I am available for a short call soon</option>
                            <option value="morning">Morning (8am–12pm local)</option>
                            <option value="afternoon">Afternoon (12pm–5pm local)</option>
                            <option value="evening">Evening (5pm–8pm local)</option>
                            <option value="schedule_note">I will note a better time in the message box</option>
                        </select>
                    </div>
"""

if "ai_call_consent" not in html:
    needle = (
        '<button type="submit" class="w-full bg-gray-900 text-white px-6 py-3 '
        'rounded-full hover:bg-gray-800 transition">Submit for Cash Offer</button>'
    )
    if needle not in html:
        raise SystemExit("submit button not found")
    html = html.replace(needle, disclaimer + "\n" + needle)
    print("inserted form disclaimer + call preference")
else:
    print("disclaimer already present")

chat_widget = r"""
    <!-- FPI AI Chatbot (lead capture) -->
    <div id="fpi-chat-root" class="fixed bottom-4 right-4 z-50" style="font-family: Arial, sans-serif;">
      <button id="fpi-chat-toggle" type="button" class="bg-yellow-500 text-gray-900 px-4 py-3 rounded-full shadow-lg font-semibold hover:bg-yellow-600">
        Chat with us
      </button>
      <div id="fpi-chat-panel" class="hidden mt-2 w-80 sm:w-96 bg-white border border-gray-300 rounded-lg shadow-2xl overflow-hidden">
        <div class="bg-gray-900 text-white px-3 py-2 flex justify-between items-center">
          <div>
            <div class="font-semibold text-sm">FPI Assistant</div>
            <div class="text-xs text-gray-300">AI chat · we buy houses for cash</div>
          </div>
          <button id="fpi-chat-close" type="button" class="text-white text-xl leading-none">&times;</button>
        </div>
        <div id="fpi-chat-log" class="h-72 overflow-y-auto p-3 text-sm space-y-2 bg-gray-50"></div>
        <div class="p-2 border-t bg-white">
          <p class="text-xs text-gray-600 mb-1">By continuing you agree an AI may assist and that we may call/text the number you provide about your property.</p>
          <form id="fpi-chat-form" class="flex gap-1">
            <input id="fpi-chat-input" type="text" autocomplete="off" placeholder="Type a message…" class="flex-1 border rounded px-2 py-2 text-sm" />
            <button type="submit" class="bg-gray-900 text-white px-3 py-2 rounded text-sm">Send</button>
          </form>
        </div>
      </div>
    </div>
    <script>
    (function(){
      const toggle = document.getElementById("fpi-chat-toggle");
      const panel = document.getElementById("fpi-chat-panel");
      const closeBtn = document.getElementById("fpi-chat-close");
      const log = document.getElementById("fpi-chat-log");
      const form = document.getElementById("fpi-chat-form");
      const input = document.getElementById("fpi-chat-input");
      const state = { name: "", phone: "", address: "", step: "greet" };

      function add(who, text){
        const d = document.createElement("div");
        d.className = who === "bot" ? "bg-white border rounded p-2 text-gray-800" : "bg-yellow-100 rounded p-2 text-gray-900 ml-6";
        d.textContent = text;
        log.appendChild(d);
        log.scrollTop = log.scrollHeight;
      }

      function openChat(){
        panel.classList.remove("hidden");
        if (state.step === "greet" && log.childElementCount === 0) {
          add("bot", "Hi — I am the First Property Investment AI assistant (not a human). We buy houses for cash as-is.");
          add("bot", "I can answer quick questions and take your info so Alex (our AI intake agent) can call you. What is your first name?");
          state.step = "name";
        }
      }
      toggle.addEventListener("click", openChat);
      closeBtn.addEventListener("click", function(){ panel.classList.add("hidden"); });

      function looksPhone(s){
        const d = (s||"").replace(/\D/g,"");
        return d.length >= 10;
      }

      async function submitLead(){
        try {
          const body = new URLSearchParams({
            name: state.name || "Chat Lead",
            phone: state.phone,
            email: "chat-lead@firstpropertyinvestment.us",
            address: state.address || "Not provided yet",
            message: "Website chatbot lead. AI consent via chat. Request callback.",
            ai_call_consent: "yes",
            call_preference: "short_call_now",
            source: "website_chatbot"
          });
          await fetch("/send.php", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: body });
          add("bot", "Thanks — we received your info. Alex (AI) or our team will reach out at " + state.phone + ". You can also use the form on this page anytime.");
          state.step = "done";
        } catch (e) {
          add("bot", "I could not submit just now. Please use the cash offer form on this page or call us.");
        }
      }

      form.addEventListener("submit", function(ev){
        ev.preventDefault();
        const text = (input.value || "").trim();
        if (!text) return;
        add("user", text);
        input.value = "";
        const lower = text.toLowerCase();

        if (state.step === "done") {
          add("bot", "We already have your number. Use the form below if you want to add property details.");
          return;
        }
        if (/(human|real person)/.test(lower)) {
          add("bot", "You can request a human anytime. Leave your phone and we will have a person follow up. What is the best number?");
          state.step = "phone";
          return;
        }
        if (/(how it works|process|closing|as-is|cash)/.test(lower)) {
          add("bot", "We buy houses for cash, often as-is. No obligation cash offer path. Typical close targets are about 30-45 days subject to title. Want Alex (AI) to call you? I just need your phone.");
          if (!state.phone) state.step = state.name ? "phone" : "name";
          return;
        }
        if (state.step === "name") {
          state.name = text;
          add("bot", "Thanks, " + state.name + ". What is the best mobile number for a call?");
          state.step = "phone";
          return;
        }
        if (state.step === "phone") {
          if (!looksPhone(text)) {
            add("bot", "Please enter a valid 10-digit phone number.");
            return;
          }
          state.phone = text;
          add("bot", "Got it. Optional: property address (or type skip).");
          state.step = "address";
          return;
        }
        if (state.step === "address") {
          if (lower !== "skip") state.address = text;
          add("bot", "By sharing your number you agree an AI from First Property Investment may call or text you about selling your property. Submitting now…");
          submitLead();
          return;
        }
        add("bot", "I can explain our cash offer process or take your phone for a callback. What is your name?");
        state.step = "name";
      });
    })();
    </script>
"""

if "fpi-chat-root" not in html:
    html = html.replace("</body>", chat_widget + "\n</body>")
    print("inserted chatbot widget")
else:
    print("chatbot already present")

html = html.replace(
    "&copy; 2025 First Property Investment", "&copy; 2026 First Property Investment"
)
(base / "index.html").write_text(html, encoding="utf-8")
print("wrote index.html", len(html))

send_php = """<?php
// send.php - Form + chatbot handler for First Property Investment
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = htmlspecialchars(trim($_POST['name'] ?? ''));
    $email = htmlspecialchars(trim($_POST['email'] ?? ''));
    $phone = htmlspecialchars(trim($_POST['phone'] ?? ''));
    $address = htmlspecialchars(trim($_POST['address'] ?? ''));
    $message = htmlspecialchars(trim($_POST['message'] ?? ''));
    $ai_consent = htmlspecialchars(trim($_POST['ai_call_consent'] ?? ''));
    $call_pref = htmlspecialchars(trim($_POST['call_preference'] ?? ''));
    $source = htmlspecialchars(trim($_POST['source'] ?? 'website_form'));

    if ($name === '' || $phone === '') {
        http_response_code(400);
        die('Error: Name and phone are required.');
    }
    if ($email === '') {
        $email = 'no-email@firstpropertyinvestment.us';
    }

    $to = 'shane.a.miller@live.com';
    $subject = 'FPI lead [' . $source . '] ' . $name;
    $headers = implode("\\r\\n", array(
        'From: website@firstpropertyinvestment.us',
        'Reply-To: ' . $email,
        'X-Mailer: PHP/' . phpversion(),
        'Content-Type: text/plain; charset=UTF-8'
    ));

    $status_hint = ($ai_consent === 'yes') ? 'APPROVED_LEAD_SENDING_ALEX' : 'NEW_LISA_LEAD';
    $body = "New FPI website lead\\n\\n"
        . "Source: $source\\n"
        . "Full Name: $name\\n"
        . "Email: $email\\n"
        . "Phone: $phone\\n"
        . "Property Address: $address\\n"
        . "AI call consent: $ai_consent\\n"
        . "Call preference: $call_pref\\n"
        . "About Property: $message\\n\\n"
        . "CRM hint status: $status_hint\\n"
        . "Submitted: " . date('c') . "\\n";
    $body = str_replace("\\\\n", "\\n", $body);

    $dropDir = '/var/www/firstpropertyinvestment.us/leads-inbox';
    if (!is_dir($dropDir)) {
        @mkdir($dropDir, 0755, true);
    }
    $row = json_encode(array(
        'source' => $source,
        'name' => $name,
        'email' => $email,
        'phone' => $phone,
        'address' => $address,
        'message' => $message,
        'ai_call_consent' => $ai_consent,
        'call_preference' => $call_pref,
        'status_hint' => $status_hint,
        'submitted_at' => date('c'),
    ), JSON_UNESCAPED_SLASHES);
    if ($row !== false) {
        @file_put_contents($dropDir . '/leads.jsonl', $row . PHP_EOL, FILE_APPEND | LOCK_EX);
    }

    @mail($to, $subject, $body, $headers);

    if ($source === 'website_chatbot') {
        header('Content-Type: application/json');
        echo json_encode(array('ok' => true));
        exit;
    }
    header('Location: thank-you.html');
    exit;
}
header('Location: index.html');
exit;
"""

# Fix PHP body newlines properly without double-escape mess
send_php = r"""<?php
// send.php - Form + chatbot handler for First Property Investment
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = htmlspecialchars(trim($_POST['name'] ?? ''));
    $email = htmlspecialchars(trim($_POST['email'] ?? ''));
    $phone = htmlspecialchars(trim($_POST['phone'] ?? ''));
    $address = htmlspecialchars(trim($_POST['address'] ?? ''));
    $message = htmlspecialchars(trim($_POST['message'] ?? ''));
    $ai_consent = htmlspecialchars(trim($_POST['ai_call_consent'] ?? ''));
    $call_pref = htmlspecialchars(trim($_POST['call_preference'] ?? ''));
    $source = htmlspecialchars(trim($_POST['source'] ?? 'website_form'));

    if ($name === '' || $phone === '') {
        http_response_code(400);
        die('Error: Name and phone are required.');
    }
    if ($email === '') {
        $email = 'no-email@firstpropertyinvestment.us';
    }

    $to = 'shane.a.miller@live.com';
    $subject = 'FPI lead [' . $source . '] ' . $name;
    $headers = implode("\r\n", array(
        'From: website@firstpropertyinvestment.us',
        'Reply-To: ' . $email,
        'X-Mailer: PHP/' . phpversion(),
        'Content-Type: text/plain; charset=UTF-8'
    ));

    $status_hint = ($ai_consent === 'yes') ? 'APPROVED_LEAD_SENDING_ALEX' : 'NEW_LISA_LEAD';
    $body = "New FPI website lead\n\n"
        . "Source: $source\n"
        . "Full Name: $name\n"
        . "Email: $email\n"
        . "Phone: $phone\n"
        . "Property Address: $address\n"
        . "AI call consent: $ai_consent\n"
        . "Call preference: $call_pref\n"
        . "About Property: $message\n\n"
        . "CRM hint status: $status_hint\n"
        . "Submitted: " . date('c') . "\n";

    $dropDir = '/var/www/firstpropertyinvestment.us/leads-inbox';
    if (!is_dir($dropDir)) {
        @mkdir($dropDir, 0755, true);
    }
    $row = json_encode(array(
        'source' => $source,
        'name' => $name,
        'email' => $email,
        'phone' => $phone,
        'address' => $address,
        'message' => $message,
        'ai_call_consent' => $ai_consent,
        'call_preference' => $call_pref,
        'status_hint' => $status_hint,
        'submitted_at' => date('c'),
    ), JSON_UNESCAPED_SLASHES);
    if ($row !== false) {
        @file_put_contents($dropDir . '/leads.jsonl', $row . PHP_EOL, FILE_APPEND | LOCK_EX);
    }

    @mail($to, $subject, $body, $headers);

    if ($source === 'website_chatbot') {
        header('Content-Type: application/json');
        echo json_encode(array('ok' => true));
        exit;
    }
    header('Location: thank-you.html');
    exit;
}
header('Location: index.html');
exit;
"""
(base / "send.php").write_text(send_php, encoding="utf-8")
os.chmod(base / "send.php", 0o755)
print("wrote send.php")

inbox = base / "leads-inbox"
inbox.mkdir(exist_ok=True)
try:
    import pwd
    import grp

    uid = pwd.getpwnam("www-data").pw_uid
    gid = grp.getgrnam("www-data").gr_gid
    os.chown(inbox, uid, gid)
    os.chmod(inbox, 0o755)
    print("leads-inbox owned www-data")
except KeyError:
    os.chmod(inbox, 0o777)
    print("leads-inbox mode 777")

r = subprocess.run(["php", "-l", str(base / "send.php")], capture_output=True, text=True)
print((r.stdout or r.stderr).strip())

# verify markers
text = (base / "index.html").read_text(encoding="utf-8", errors="replace")
for m in ("ai_call_consent", "call_preference", "fpi-chat-root", "AI assistant disclosure"):
    print(m, "OK" if m in text else "MISSING")
