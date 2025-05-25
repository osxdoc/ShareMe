import os
import subprocess
import configparser
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.config['SECRET_KEY'] = 'd1e5ecr3t3s4mb4shareme2025!'
# Wähle für Produktion einen eigenen, langen, zufälligen Wert!
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# User class for Flask-Login
class User(UserMixin):
    def __init__(self, id, username, password_hash, is_admin=False):
        self.id = id
        self.username = username
        self.password_hash = password_hash
        self.is_admin = is_admin

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

# Simple user database - in production, use a real database
users = {
    '1': User('1', 'admin', generate_password_hash('admin'), True)
}

@login_manager.user_loader
def load_user(user_id):
    return users.get(user_id)

# Routes
@app.route('/')
@login_required
def index():
    return render_template('index.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        for user_id, user in users.items():
            if user.username == username and user.check_password(password):
                login_user(user)
                return redirect(url_for('index'))
        
        flash('Invalid username or password')
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

# Samba configuration functions
def get_samba_config():
    config = configparser.ConfigParser(strict=False)
    config.read('/etc/samba/smb.conf')
    return config

def save_samba_config(config):
    with open('/etc/samba/smb.conf', 'w') as f:
        config.write(f)
    # Restart Samba service
    subprocess.run(['systemctl', 'restart', 'smbd'])
    subprocess.run(['systemctl', 'restart', 'nmbd'])

@app.route('/shares')
@login_required
def shares():
    config = get_samba_config()
    shares_list = []
    
    for section in config.sections():
        if section not in ['global', 'homes', 'printers', 'print$']:
            share_info = {
                'name': section,
                'path': config.get(section, 'path', fallback=''),
                'comment': config.get(section, 'comment', fallback=''),
                'browseable': config.getboolean(section, 'browseable', fallback=True),
                'read_only': config.getboolean(section, 'read only', fallback=False),
                'guest_ok': config.getboolean(section, 'guest ok', fallback=False)
            }
            shares_list.append(share_info)
    
    return render_template('shares.html', shares=shares_list)

@app.route('/shares/add', methods=['GET', 'POST'])
@login_required
def add_share():
    if not current_user.is_admin:
        flash('Admin privileges required')
        return redirect(url_for('shares'))
        
    if request.method == 'POST':
        share_name = request.form.get('name')
        path = request.form.get('path')
        comment = request.form.get('comment')
        browseable = 'browseable' in request.form
        read_only = 'read_only' in request.form
        guest_ok = 'guest_ok' in request.form
        
        config = get_samba_config()
        
        if share_name in config:
            flash(f'Share {share_name} already exists')
            return redirect(url_for('add_share'))
        
        config[share_name] = {
            'path': path,
            'comment': comment,
            'browseable': 'yes' if browseable else 'no',
            'read only': 'yes' if read_only else 'no',
            'guest ok': 'yes' if guest_ok else 'no'
        }
        
        try:
            save_samba_config(config)
            flash(f'Share {share_name} added successfully')
            return redirect(url_for('shares'))
        except Exception as e:
            flash(f'Error adding share: {str(e)}')
    
    return render_template('add_share.html')

@app.route('/shares/edit/<share_name>', methods=['GET', 'POST'])
@login_required
def edit_share(share_name):
    if not current_user.is_admin:
        flash('Admin privileges required')
        return redirect(url_for('shares'))
        
    config = get_samba_config()
    
    if share_name not in config:
        flash(f'Share {share_name} not found')
        return redirect(url_for('shares'))
    
    if request.method == 'POST':
        path = request.form.get('path')
        comment = request.form.get('comment')
        browseable = 'browseable' in request.form
        read_only = 'read_only' in request.form
        guest_ok = 'guest_ok' in request.form
        
        config[share_name]['path'] = path
        config[share_name]['comment'] = comment
        config[share_name]['browseable'] = 'yes' if browseable else 'no'
        config[share_name]['read only'] = 'yes' if read_only else 'no'
        config[share_name]['guest ok'] = 'yes' if guest_ok else 'no'
        
        try:
            save_samba_config(config)
            flash(f'Share {share_name} updated successfully')
            return redirect(url_for('shares'))
        except Exception as e:
            flash(f'Error updating share: {str(e)}')
    
    share_info = {
        'name': share_name,
        'path': config.get(share_name, 'path', fallback=''),
        'comment': config.get(share_name, 'comment', fallback=''),
        'browseable': config.getboolean(share_name, 'browseable', fallback=True),
        'read_only': config.getboolean(share_name, 'read only', fallback=False),
        'guest_ok': config.getboolean(share_name, 'guest ok', fallback=False)
    }
    
    return render_template('edit_share.html', share=share_info)

@app.route('/shares/delete/<share_name>', methods=['POST'])
@login_required
def delete_share(share_name):
    if not current_user.is_admin:
        flash('Admin privileges required')
        return redirect(url_for('shares'))
        
    config = get_samba_config()
    
    if share_name not in config:
        flash(f'Share {share_name} not found')
        return redirect(url_for('shares'))
    
    config.remove_section(share_name)
    
    try:
        save_samba_config(config)
        flash(f'Share {share_name} deleted successfully')
    except Exception as e:
        flash(f'Error deleting share: {str(e)}')
    
    return redirect(url_for('shares'))

# Samba user management
@app.route('/users')
@login_required
def users_list():
    if not current_user.is_admin:
        flash('Admin privileges required')
        return redirect(url_for('index'))
        
    try:
        # Get Samba users using pdbedit
        result = subprocess.run(['pdbedit', '-L', '-v'], capture_output=True, text=True)
        output = result.stdout
        
        # Parse the output to extract user information
        samba_users = []
        current_samba_user = {}
        
        for line in output.splitlines():
            line = line.strip()
            if line.startswith('Unix username:'):
                if current_samba_user:
                    samba_users.append(current_samba_user)
                current_samba_user = {'username': line.split(':', 1)[1].strip()}
            elif line.startswith('Account Flags:'):
                current_samba_user['flags'] = line.split(':', 1)[1].strip()
            elif line.startswith('User SID:'):
                current_samba_user['sid'] = line.split(':', 1)[1].strip()
        
        if current_samba_user:
            samba_users.append(current_samba_user)
        
        return render_template('users.html', users=samba_users)
    except Exception as e:
        flash(f'Error retrieving users: {str(e)}')
        return render_template('users.html', users=[])

@app.route('/users/add', methods=['GET', 'POST'])
@login_required
def add_user():
    if not current_user.is_admin:
        flash('Admin privileges required')
        return redirect(url_for('index'))
        
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        try:
            # Add user to Samba using smbpasswd
            process = subprocess.Popen(['smbpasswd', '-a', username], 
                                      stdin=subprocess.PIPE, 
                                      stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE,
                                      text=True)
            
            # Send password twice (for confirmation)
            process.communicate(f"{password}\n{password}\n")
            
            if process.returncode == 0:
                flash(f'User {username} added successfully')
                return redirect(url_for('users_list'))
            else:
                flash(f'Error adding user: process returned {process.returncode}')
        except Exception as e:
            flash(f'Error adding user: {str(e)}')
    
    return render_template('add_user.html')

@app.route('/users/delete/<username>', methods=['POST'])
@login_required
def delete_user(username):
    if not current_user.is_admin:
        flash('Admin privileges required')
        return redirect(url_for('index'))
        
    try:
        # Delete user from Samba using smbpasswd
        result = subprocess.run(['smbpasswd', '-x', username], capture_output=True, text=True)
        
        if result.returncode == 0:
            flash(f'User {username} deleted successfully')
        else:
            flash(f'Error deleting user: {result.stderr}')
    except Exception as e:
        flash(f'Error deleting user: {str(e)}')
    
    return redirect(url_for('users_list'))

@app.route('/users/reset_password/<username>', methods=['GET', 'POST'])
@login_required
def reset_password(username):
    if not current_user.is_admin:
        flash('Admin privileges required')
        return redirect(url_for('index'))
        
    if request.method == 'POST':
        password = request.form.get('password')
        
        try:
            # Reset user password using smbpasswd
            process = subprocess.Popen(['smbpasswd', username], 
                                      stdin=subprocess.PIPE, 
                                      stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE,
                                      text=True)
            
            # Send password twice (for confirmation)
            process.communicate(f"{password}\n{password}\n")
            
            if process.returncode == 0:
                flash(f'Password for {username} reset successfully')
                return redirect(url_for('users_list'))
            else:
                flash(f'Error resetting password: process returned {process.returncode}')
        except Exception as e:
            flash(f'Error resetting password: {str(e)}')
    
    return render_template('reset_password.html', username=username)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
