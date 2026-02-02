from flask import Flask, request, render_template_string
import os
import subprocess
from datetime import datetime

app = Flask(__name__)

# --- CONFIGURATION ---
EMAIL_FILE = "/home/gns3/.gns3_student_email"
IP_FILE = "/home/gns3/.gns3_access_ip"
PROJECTS_DIR = "/opt/gns3/projects"
BACKUP_DIR = "/gns-backup"
BACKUP_SCRIPT = "/usr/local/bin/gns3_backup.sh"
RELAY = "smtp.educloud.fontysict.nl"
FROM = "noreply@fontysict.nl"

def get_disk_info():
    try:
        output = subprocess.check_output(['df', '-h', '/']).decode('utf-8').splitlines()[1]
        parts = output.split()
        return {"total": parts[1], "used": parts[2], "available": parts[3], "percent": parts[4]}
    except:
        return {"total": "?", "used": "?", "available": "?", "percent": "?"}

def get_active_projects():
    project_list = []
    try:
        if os.path.exists(PROJECTS_DIR):
            for d in os.listdir(PROJECTS_DIR):
                d_path = os.path.join(PROJECTS_DIR, d)
                if os.path.isdir(d_path):
                    for f in os.listdir(d_path):
                        if f.endswith(".gns3"):
                            project_list.append(f.replace('.gns3', ''))
                            break
    except: pass
    return project_list

def get_backup_info():
    backups = []
    last_run = "Never"
    script_active = os.path.exists(BACKUP_SCRIPT)
    
    if os.path.exists(BACKUP_DIR):
        files = [f for f in os.listdir(BACKUP_DIR) if f.endswith('.gns3')]
        files_with_stats = []
        for f in files:
            path = os.path.join(BACKUP_DIR, f)
            stat = os.stat(path)
            display_name = f.split('_20')[0].replace('.gns3', '')
            files_with_stats.append({
                "filename": f,
                "project_name": display_name,
                "mtime": stat.st_mtime,
                "size": f"{round(stat.st_size / 1024, 1)} KB"
            })
        files_with_stats.sort(key=lambda x: x['mtime'], reverse=True)
        backups = files_with_stats[:5]
        if backups:
            last_run = datetime.fromtimestamp(backups[0]['mtime']).strftime('%Y-%m-%d %H:%M:%S')
            
    return {"files": backups, "last_run": last_run, "active": script_active}

HTML_PAGE = """
<!DOCTYPE html>
<html>
<head>
    <title>GNS3 Server Control</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; display: flex; justify-content: center; padding: 20px; }
        .card { background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.1); width: 100%; max-width: 550px; text-align: center; }
        h2 { color: #004681; margin-top: 0; margin-bottom: 20px; }
        .section-title { font-weight: bold; color: #495057; margin-bottom: 10px; display: block; border-bottom: 1px solid #dee2e6; padding-bottom: 5px; text-align: left; }
        .info-box { background: #e7f3ff; padding: 15px; border-radius: 8px; margin-bottom: 20px; border: 1px solid #b3d7ff; }
        .stats-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 20px; }
        .data-box { background: #f8f9fa; padding: 12px; border-radius: 8px; text-align: left; border: 1px solid #dee2e6; font-size: 0.85em; }
        .project-tag { display: inline-block; background: #004681; color: white; padding: 2px 8px; border-radius: 4px; margin: 2px; font-size: 0.8em; }
        .backup-list { list-style: none; padding: 0; margin: 0; font-size: 0.85em; }
        .backup-item { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px dotted #ccc; align-items: center; }
        .project-label { font-weight: bold; color: #004681; display: block; }
        .file-label { font-size: 0.75em; color: #777; font-family: monospace; }
        .status-badge { font-size: 0.75em; padding: 2px 6px; border-radius: 4px; float: right; }
        .bg-success { background: #d4edda; color: #155724; }
        
        /* Buttons container */
        .button-group { display: flex; flex-direction: column; gap: 10px; margin-bottom: 20px; }
        .btn-link { display: block; background: #28a745; color: white; padding: 12px; text-decoration: none; border-radius: 6px; font-weight: bold; box-sizing: border-box; text-align: center; }
        .btn-link:hover { background: #218838; }
        
        form { text-align: left; margin-top: 15px; border-top: 1px solid #eee; padding-top: 15px; }
        label { font-weight: bold; display: block; margin-bottom: 5px; color: #555; font-size: 0.9em; }
        input[type="email"] { width: 100%; padding: 10px; margin-bottom: 10px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; }
        .btn-action { border: none; padding: 10px; border-radius: 6px; cursor: pointer; width: 100%; font-weight: bold; transition: 0.2s; margin-bottom: 8px; }
        .btn-save { background: #004681; color: white; }
        .btn-test { background: #6c757d; color: white; }
        .status-msg { margin-top: 10px; padding: 8px; border-radius: 6px; font-weight: bold; font-size: 0.85em; text-align: center; }
        .success { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class="card">
        <h2>GNS3 Server Control</h2>
        <div class="info-box">
            <strong>Access IP:</strong> <code style="color: #d63384;">{{ access_ip }}</code><br>
            <div style="margin-top:10px;">
                <strong>Current Projects:</strong><br>
                {% for name in active_project_names %}
                    <span class="project-tag">{{ name }}</span>
                {% else %}
                    <code style="font-size: 0.8em;">No active projects</code>
                {% endfor %}
            </div>
        </div>
        <div class="stats-grid">
            <div class="data-box">
                <span class="section-title">Disk Storage</span>
                Used: <strong>{{ disk.used }} ({{ disk.percent }})</strong><br>
                Free: <strong>{{ disk.available }}</strong>
            </div>
            <div class="data-box">
                <span class="section-title">Backup System
                    <span class="status-badge {{ 'bg-success' if backup.active else '' }}">
                        {{ 'Active' if backup.active else 'Inactive' }}
                    </span>
                </span>
                Last backup: <br><strong>{{ backup.last_run }}</strong>
            </div>
        </div>
        <div class="data-box" style="margin-bottom: 20px;">
            <span class="section-title">Latest Backups</span>
            <ul class="backup-list">
                {% for b in backup.files %}
                <li class="backup-item">
                    <div style="text-align: left;">
                        <span class="project-label">{{ b.project_name }}</span>
                        <span class="file-label">{{ b.filename }}</span>
                    </div>
                    <span style="color: #666; font-weight: bold;">{{ b.size }}</span>
                </li>
                {% else %}
                <li class="backup-item">No backups available.</li>
                {% endfor %}
            </ul>
        </div>

        <div class="button-group">
            <a href="http://{{ access_ip }}/static/web-ui/server/1/systemstatus" class="btn-link" target="_blank">View System Status</a>
            <a href="http://{{ access_ip }}/static/web-ui/server/1/projects" class="btn-link" target="_blank">Manage Projects (Web UI)</a>
        </div>

        <form method="POST" action="/">
            <label>Email Notification Settings:</label>
            <input type="email" name="email" value="{{ current_email }}" placeholder="student@fontys.nl" required>
            <button type="submit" class="btn-action btn-save">Update Email</button>
        </form>
        <form method="POST" action="/test_mail">
            <button type="submit" class="btn-action btn-test">Send Connectivity Test</button>
        </form>
        {% if status %}
            <div class="status-msg {{ 'success' if 'Success' in status else 'error' }}">
                {{ status }}
            </div>
        {% endif %}
    </div>
</body>
</html>
"""

@app.route('/', methods=['GET', 'POST'])
def index():
    access_ip = request.host.split(':')[0]
    disk = get_disk_info()
    backup = get_backup_info()
    active_project_names = get_active_projects()
    status = request.args.get('status')
    
    if request.method == 'POST':
        email = request.form.get('email', '').strip()
        with open(EMAIL_FILE, "w") as f: f.write(email)
        with open(IP_FILE, "w") as f: f.write(access_ip)
        os.chown(EMAIL_FILE, 1000, 1000)
        os.chown(IP_FILE, 1000, 1000)
        status = "Success: Settings saved!"

    current_email = ""
    if os.path.exists(EMAIL_FILE):
        with open(EMAIL_FILE, "r") as f: current_email = f.read().strip()
            
    return render_template_string(HTML_PAGE, access_ip=access_ip, current_email=current_email, status=status, disk=disk, backup=backup, active_project_names=active_project_names)

@app.route('/test_mail', methods=['POST'])
def test_mail():
    access_ip = request.host.split(':')[0]
    if not os.path.exists(EMAIL_FILE):
        return index()
    with open(EMAIL_FILE, "r") as f: email = f.read().strip()
    cmd = ["swaks", "--to", email, "--from", FROM, "--server", RELAY, "--port", "25", "--header", "Subject: GNS3 Setup Test", "--body", f"Test successful for {access_ip}"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    status = "Success: Test email sent!" if res.returncode == 0 else "Error: Delivery failed."
    return render_template_string(HTML_PAGE, access_ip=access_ip, current_email=email, status=status, disk=get_disk_info(), backup=get_backup_info(), active_project_names=get_active_projects())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
