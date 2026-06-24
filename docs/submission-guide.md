# How to Submit Items to the Repository
### Harare Polytechnic Institutional Repository — User Guide

---

## Who Can Submit?

| Role | Can Submit To |
|---|---|
| Student | Their faculty collection (with supervisor approval) |
| Lecturer / Researcher | All faculty collections |
| Librarian / Admin | All collections |

---

## Required Metadata Fields

When submitting any item, fill in these fields:

| Field | Example | Required? |
|---|---|---|
| **Title** | "Design of Harare CBD Flyover Bridge" | Yes |
| **Author(s)** | "Moyo, Tendai" | Yes |
| **Date** | 2024-05 | Yes |
| **Abstract** | 150–300 words describing the work | Yes |
| **Subject / Keywords** | civil engineering; bridges; Zimbabwe | Yes |
| **Type** | Final Year Project / Thesis / Research Paper | Yes |
| **Language** | English | Yes |
| **Department / Faculty** | Faculty of Engineering | Yes |
| **Supervisor** | Eng. Chikwanda, P. | For FYPs |
| **Degree** | B.Tech Civil Engineering | For Theses |
| **Rights** | Copyright Harare Polytechnic 2024 | Yes |

---

## Step-by-Step: Submit via Web Browser

1. Open `http://192.168.26.3/` in your browser
2. Click **Login** → enter your email and password
3. Click **Submit** in the top menu
4. Select the correct **Collection**:
   ```
   Academic Departments
     └── Faculty of Engineering
           └── Final Year Projects — Engineering  ← choose this
   ```
5. Fill in all required metadata fields
6. Upload your file(s) — PDF is preferred
7. Review and click **Deposit Item**
8. Your submission goes to the reviewer queue

---

## File Formats Accepted

| Content Type | Preferred Format | Also Accepted |
|---|---|---|
| Written reports / theses | PDF | DOCX |
| Spreadsheets / data | XLSX | CSV, ODS |
| Images | JPEG, PNG | TIFF, BMP |
| Drawings / CAD | PDF export | DWG |
| Presentations | PDF export | PPTX |
| Video | MP4 (H.264) | AVI, MOV |
| Audio | MP3 | WAV |
| Source code | ZIP archive | — |

**Maximum file size:** 500MB per file

---

## Batch Import (For Librarians)

To import many items at once using the CSV template:

```bash
# 1. Fill in docs/batch-import-template.csv with your items
# 2. Place PDF files in a folder named 'files/'
# 3. Run the import:
/dspace/bin/dspace import \
    --add \
    --eperson library@hrepoly.ac.zw \
    --collection <collection-handle> \
    --source /path/to/import-package/ \
    --mapfile /tmp/import-map.txt
```

---

## Collection Structure

```
Harare Polytechnic Institutional Repository
│
├── Academic Departments
│   ├── Faculty of Engineering
│   │   ├── Final Year Projects — Engineering
│   │   ├── Theses and Dissertations — Engineering
│   │   └── Research Papers — Engineering
│   ├── Faculty of ICT & Electronics
│   │   ├── Final Year Projects — ICT
│   │   ├── Theses and Dissertations — ICT
│   │   └── Software Projects & Source Code
│   ├── Faculty of Business Management
│   │   ├── Final Year Projects — Business
│   │   ├── Theses and Dissertations — Business
│   │   └── Case Studies
│   ├── Faculty of Applied Sciences
│   │   ├── Final Year Projects — Sciences
│   │   └── Research Papers — Sciences
│   ├── Faculty of Fashion & Textiles
│   │   ├── Final Year Projects — Fashion
│   │   └── Design Portfolios
│   └── Faculty of Built Environment
│       ├── Final Year Projects — Built Environment
│       └── Theses — Built Environment
│
├── Research & Innovation Hub
│   ├── Staff Research Publications
│   ├── Conference Proceedings
│   ├── Innovation & Patents
│   └── Industry Collaboration Reports
│
├── Library Collections
│   ├── Local Newspapers & Periodicals
│   ├── Zimbabwe Grey Literature
│   ├── Historical Documents
│   └── Audio-Visual Materials
│
└── Student Works
    ├── Award-Winning Projects
    └── Student Exhibitions
```
