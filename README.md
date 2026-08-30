# SwingGrade

## Problem

Amateur golfers frequently struggle to diagnose swing flaws without expensive launch monitors or in-person coaching. Existing mobile swing analysis apps often overwhelm users with raw, uncontextualized biomechanical data or provide generic tips that fail to address the underlying root cause of swing faults. Additionally, traditional capture flows require constant physical interaction with the phone, interrupting the flow of practice.

---

## Solution

SwingGrade is a hands-free, landscape iOS application that acts as an intelligent, real-time golf coach.

* **Smart Sensor Fusion & Anchor Detection**: Automatically captures swings at up to 240 FPS using audio-visual fusion (detecting the impact sound and visual strike) to anchor key frames: Address, Top of Swing, Impact, and Finish.
* **Dual-Model Vision Pipeline**: Combines Apple's Vision framework (for 19-joint human skeletal tracking) with a custom object-detection model (for club and shaft tracking).
* **Root-Cause Analysis Engine**: Compares calculated biomechanical angles, positions, and tempo ratios against an expert-calibrated reference dataset (`ProModel.json`). It isolates primary faults from mere symptoms and provides targeted drills matched to the golfer's skill level.
* **Visual Feedback & Session Memory**: Displays a color-coded skeleton (gradient from green to red based on alignment quality) alongside personalized swing scores and corrective drills, maintaining short-term context across consecutive practice swings.

---

## Tech Stack

* **Platform**: iOS (iOS 18.6+), Swift, SwiftUI
* **Computer Vision & Pose Tracking**: Apple Vision Framework (`VNDetectHumanBodyPoseRequest`)
* **Custom Machine Learning**: Apple Create ML / Core ML (Object Detection for golf club head and shaft tracking)
* **Audio & Video Processing**: AVFoundation (High frame-rate capture, 240 FPS video pipeline, audio spike thresholding)
* **Local Persistence**: SwiftData (Swing history, scoring metadata, snapshot storage)
* **Biomechanical Data Layer**: Structured JSON knowledge base (`ProModel.json`)

---

## Project Lifecycle & Architecture

### 1. Dataset Creation & Cleaning

* **Club Detection Dataset**: Curated and annotated a specialized dataset of 900+ high-definition frames captured from multiple golf swing angles (Down-the-Line and Head-On) across varied lighting conditions.
* **Annotation & Verification**: Labeled bounding boxes and coordinates for the clubhead and shaft across all key phases of the swing arc.
* **Biomechanics Reference Engine (`ProModel.json`)**: Researched and compiled PGA/LPGA tour benchmarks, standard acceptable tolerances, beginner vs. advanced priority weightings, symptom-to-root-cause mappings, and level-specific drills across 5 distinct club categories:
* Driver
* Fairway Woods & Hybrids
* Long Irons
* Mid & Short Irons
* Wedges (Pitching, Sand, Lob)



### 2. Model Training & Analysis Math

* **Create ML Club Detector**: Trained and exported a Core ML model optimized for real-time inference on Apple Neural Engine to track club positioning alongside body joints.
* **Vector & Angular Geometry**: Formulated spatial calculations mapping raw $(x, y)$ coordinates to core golf biomechanics:
* **Setup & Posture**: Spine bend/tilt angles at address, stance width, head position baseline.
* **Kinematic Sequence & Plane**: Takeaway path, shoulder plane tilt at top, trail leg flex change, shaft angle at top.
* **Impact & Release**: Angle of attack, club path direction, horizontal hip sway/bump, lag retention/early release (casting), lead wrist extension/cupping.
* **Timing & Follow-Through**: Backswing-to-downswing tempo ratios (3:1 standard), lead arm extension (chicken wing detection), and finish balance stability.


* **Scoring Algorithm**: Graded metrics against normalized target ranges, penalizing extreme deviations and isolating root flaws using dependency graph tagging (`root_cause_for` vs. `symptom_of`).

### 3. Application Development

* **Hands-Free Capture Pipeline**: Implemented a passive background listening and recording loop that identifies address poses, triggers on impact audio cues, trims non-swing footage, and supports voice commands ("Again", "Record") for continuous practice.
* **Interactive Analysis UI**: Built a split-screen dashboard displaying:
* Slow-motion video playback with dynamic skeletal joint overlays.
* Color-coded feedback reflecting joint-level alignment quality.
* Primary flaw diagnosis with plain-language explanations and difficulty-tagged drills.


* **History & Profile Management**: Integrated SwiftData storage allowing users to review historical swing scorecards, metric trends, and personalized skeletal snapshots over time.
