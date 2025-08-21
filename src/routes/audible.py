import os
import json
import uuid
import tempfile
from datetime import datetime
from flask import Blueprint, request, jsonify, render_template, redirect, url_for
from werkzeug.utils import secure_filename
import subprocess
import re

audible_bp = Blueprint('audible', __name__)

# Configuration
UPLOAD_FOLDER = '/tmp/audible_uploads'
ANALYSIS_FOLDER = '/tmp/audible_analysis'
ALLOWED_EXTENSIONS = {'txt', 'pdf', 'epub', 'mobi', 'azw', 'azw3'}

# Ensure directories exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(ANALYSIS_FOLDER, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def analyze_book_content(file_path, user_name, user_email):
    """Comprehensive book analysis function"""
    try:
        # Read file content
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Basic analysis
        word_count = len(content.split())
        char_count = len(content)
        line_count = len(content.split('\n'))
        
        # Extract potential metadata
        title_match = re.search(r'(?i)title[:\s]+([^\n]+)', content[:2000])
        author_match = re.search(r'(?i)author[:\s]+([^\n]+)', content[:2000])
        
        # Estimate reading time (average 200 words per minute)
        reading_time_minutes = word_count / 200
        reading_time_hours = reading_time_minutes / 60
        
        # Generate analysis results
        analysis = {
            'project_id': str(uuid.uuid4()),
            'user_name': user_name,
            'user_email': user_email,
            'filename': os.path.basename(file_path),
            'analysis_date': datetime.now().isoformat(),
            'statistics': {
                'word_count': word_count,
                'character_count': char_count,
                'line_count': line_count,
                'estimated_reading_time_minutes': round(reading_time_minutes, 2),
                'estimated_reading_time_hours': round(reading_time_hours, 2)
            },
            'metadata': {
                'title': title_match.group(1).strip() if title_match else 'Unknown',
                'author': author_match.group(1).strip() if author_match else 'Unknown'
            },
            'content_preview': content[:500] + '...' if len(content) > 500 else content,
            'analysis_status': 'completed'
        }
        
        return analysis
    except Exception as e:
        return {
            'error': str(e),
            'analysis_status': 'failed'
        }

@audible_bp.route('/')
def index():
    """Main upload page"""
    return render_template('index.html')

@audible_bp.route('/upload', methods=['POST'])
def upload_file():
    """Handle file upload and start analysis"""
    try:
        # Get form data
        user_name = request.form.get('fullName', '')
        user_email = request.form.get('email', '')
        
        if 'bookFile' not in request.files:
            return jsonify({'error': 'No file selected'}), 400
        
        file = request.files['bookFile']
        if file.filename == '':
            return jsonify({'error': 'No file selected'}), 400
        
        if file and allowed_file(file.filename):
            # Generate unique filename
            project_id = str(uuid.uuid4())
            filename = secure_filename(file.filename)
            file_path = os.path.join(UPLOAD_FOLDER, f"{project_id}_{filename}")
            
            # Save uploaded file
            file.save(file_path)
            
            # Perform analysis
            analysis_results = analyze_book_content(file_path, user_name, user_email)
            analysis_results['project_id'] = project_id
            
            # Save analysis results
            analysis_file = os.path.join(ANALYSIS_FOLDER, f"{project_id}_analysis.json")
            with open(analysis_file, 'w') as f:
                json.dump(analysis_results, f, indent=2)
            
            # Return analysis page URL
            return redirect(url_for('audible.analyze', project_id=project_id))
        
        return jsonify({'error': 'Invalid file type'}), 400
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@audible_bp.route('/analyze/<project_id>')
def analyze(project_id):
    """Display analysis results"""
    try:
        analysis_file = os.path.join(ANALYSIS_FOLDER, f"{project_id}_analysis.json")
        
        if not os.path.exists(analysis_file):
            return "Analysis not found", 404
        
        with open(analysis_file, 'r') as f:
            analysis_data = json.load(f)
        
        return render_template('analyze.html', analysis=analysis_data)
    
    except Exception as e:
        return f"Error loading analysis: {str(e)}", 500

@audible_bp.route('/api/analysis/<project_id>')
def get_analysis_data(project_id):
    """API endpoint to get analysis data as JSON"""
    try:
        analysis_file = os.path.join(ANALYSIS_FOLDER, f"{project_id}_analysis.json")
        
        if not os.path.exists(analysis_file):
            return jsonify({'error': 'Analysis not found'}), 404
        
        with open(analysis_file, 'r') as f:
            analysis_data = json.load(f)
        
        return jsonify(analysis_data)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

