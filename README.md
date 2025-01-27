# BoookTrackerModel-for-SonarAudiobooks-
This repository focuses on a TTS-based instruction model to guide users, including the visually impaired, in positioning cameras relative to objects like books. Using real-time YOLO detection, it provides spoken instructions such as “move closer” or “move left” to help align objects. Implementations are available in Python and Flutter.

TTS-Based Camera Guidance for Object Alignment

This repository focuses on developing a text-to-speech (TTS) based instruction model that helps users, including the visually impaired, position their cameras relative to objects of interest, such as books. By using YOLO object detection, the system provides real-time audio feedback to guide users in aligning the object optimally in the camera’s view.

Key Features
	•	Real-Time Object Detection: Leverages YOLO to detect objects (e.g., books) from live video feeds.
	•	Text-to-Speech Feedback: Provides spoken instructions like “move closer” or “move left” to help position objects.
	•	Multi-Platform Support:
	•	Python: For PC or embedded systems using OpenCV and gTTS.
	•	Flutter: For mobile devices using a TFLite-converted YOLO model.

Use Cases
	•	Assist visually impaired users in aligning objects for scanning or photographing.
	•	Provide interactive guidance for positioning objects in the camera frame.
	•	Enhance workflows requiring precise object alignment (e.g., OCR, document scanning).

How It Works
	1.	Object Detection: The YOLO model detects objects in the camera feed.
	2.	Object Analysis: The system evaluates the position and size of the detected object relative to the camera’s optimal frame.
	3.	Instruction Generation: Based on the analysis, spoken instructions are generated, guiding the user to adjust the object’s position.

Implementation Details

Python
	•	Uses Ultralytics YOLO for detection, OpenCV for video streaming, and gTTS with pygame for TTS feedback.
	•	Ideal for systems with a webcam or IP camera feed.

Flutter
	•	Utilizes a TFLite-converted YOLO model for on-device detection.
	•	Provides a camera preview with bounding boxes and real-time TTS feedback using the flutter_tts plugin.
	•	Suitable for Android and iOS devices.

Getting Started

Python
	1.	Install dependencies:

pip install ultralytics opencv-python pygame gTTS


	2.	Run the detection script:

python booktracker.py


	3.	Ensure a webcam or IP camera is connected.

Flutter
	1.	Place the TFLite model and labels file in the assets/ folder.
	2.	Add required dependencies in pubspec.yaml.
	3.	Run the Flutter app:

flutter run



Future Enhancements
	•	Support for additional object classes.
	•	Improved detection performance for low-end devices.
	•	Multi-language TTS support.

License

This project is licensed under the MIT License. Feel free to use and modify it as needed.

Empowering accessibility through real-time guidance!
