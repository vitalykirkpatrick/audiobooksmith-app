# AudiobookSmith.app

A comprehensive Flask-based web application for analyzing Audible books and ebooks. Upload your book files and get detailed analysis including word count, reading time estimates, metadata extraction, and content previews.

## Features

- **File Upload Support**: Supports multiple formats including TXT, PDF, EPUB, MOBI, AZW, AZW3
- **Comprehensive Analysis**: 
  - Word count and character count
  - Estimated reading time
  - Metadata extraction (title, author)
  - Content preview
- **User-Friendly Interface**: Modern, responsive web interface
- **Analysis Results**: Detailed results page with statistics and metadata
- **Print Support**: Print-friendly analysis results

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/audiobooksmith-app.git
cd audiobooksmith-app
```

2. Create and activate a virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Run the application:
```bash
python src/main.py
```

The application will be available at `http://localhost:5000`

## Project Structure

```
audiobooksmith/
├── src/
│   ├── main.py              # Main Flask application
│   ├── routes/
│   │   ├── audible.py       # Book analysis routes
│   │   └── user.py          # User management routes
│   ├── templates/
│   │   ├── index.html       # Upload form page
│   │   └── analyze.html     # Analysis results page
│   ├── static/              # Static files
│   └── models/              # Database models
├── requirements.txt         # Python dependencies
└── README.md               # This file
```

## API Endpoints

- `GET /` - Main upload page
- `POST /upload` - Handle file upload and analysis
- `GET /analyze/<project_id>` - Display analysis results
- `GET /api/analysis/<project_id>` - Get analysis data as JSON

## Deployment

The application is designed to be deployed on various platforms:

1. **Local Development**: Use the built-in Flask development server
2. **Production**: Deploy using WSGI servers like Gunicorn or uWSGI
3. **Cloud Platforms**: Compatible with Heroku, AWS, Google Cloud, etc.

## Configuration

The application uses the following directories for file storage:
- `/tmp/audible_uploads/` - Uploaded book files
- `/tmp/audible_analysis/` - Analysis results (JSON files)

Make sure these directories have appropriate write permissions.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For support and questions, please open an issue on GitHub.

