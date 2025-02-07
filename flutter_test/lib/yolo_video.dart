import 'package:flutter_vision/flutter_vision.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

late List<CameraDescription> cameras;

class YoloVideo extends StatefulWidget {
  const YoloVideo({Key? key}) : super(key: key);

  @override
  State<YoloVideo> createState() => _YoloVideoState();
}

class _YoloVideoState extends State<YoloVideo> {
  late CameraController controller;
  late FlutterVision vision;
  List<CameraDescription> cameras = [];
  late List<Map<String, dynamic>> yoloResults;

  CameraImage? cameraImage;
  bool isDetecting = false;

  // TTS instructions
  final FlutterTts flutterTts = FlutterTts();
  String? currentState; //e.g. "left, right, etc."
  DateTime lastInstructionTime = DateTime.now();
  DateTime lastDetectionTime = DateTime.now();
  static const int instructionCooldown = 3; //seconds
  static const int noDetectionThreshold = 2; //seconds

  //confidence threshold for a valid detection
  final double confidenceThreshold = 0.3;

  // store screen size from build
  Size _screenSize = Size.zero;

  //optimal target box rations (relative to screen dimensions)
  final double widthCoverage = 0.65;
  final double heightCoverage = 0.85;

  @override
  void initState() {
    super.initState();
    yoloResults = [];
    initializeCameraAndModel();
  }

  @override
  void dispose() {
    controller.dispose();
    vision.closeYoloModel();
    super.dispose();
  }

  Future<void> initializeCameraAndModel() async {
    try {
      await Permission.camera.request();
      vision = FlutterVision();
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        debugPrint('No cameras found!');
        return;
      }
      controller = CameraController(
        cameras[0],
        ResolutionPreset.max,
      );
      await controller.initialize();

      //load yolo model
      await vision.loadYoloModel(
        labels: 'assets/coco-labels-2014_2017.txt',
        modelPath: 'assets/yolov8n_float32.tflite',
        modelVersion: "yolov8",
        numThreads: 2,
        useGpu: false,
      );
      //start detecting
      startDetection();
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> yoloOnFrame(CameraImage image) async {
    final result = await vision.yoloOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      imageHeight: 1440,
      imageWidth: 1080,
      iouThreshold: 0.4,
      confThreshold: 0.1,
      classThreshold: 0.1,
    );

    debugPrint('YOLO Detection Raw Results: $result');

    if (result.isNotEmpty) {
      setState(() {
        yoloResults = result;
        cameraImage = image;
      });
    }
    // Process the detection results (for TTS instructions)
    if (_screenSize != Size.zero) {
      processDetections(yoloResults, _screenSize);
    }
  }

  Future<void> startDetection() async {
    setState(() {
      isDetecting = true;
    });
    if (!controller.value.isStreamingImages) {
      await controller.startImageStream((image) async {
        if (isDetecting) {
          cameraImage = image;
          await yoloOnFrame(image);
        }
      });
    }
  }

  // Process the detection results and issue TTS instructions.
  void processDetections(
      List<Map<String, dynamic>> detections, Size screenSize) {
    final bookDetections = detections.where((d) {
      if (d.containsKey("cls") &&
          d["cls"] is List &&
          d["cls"].isNotEmpty &&
          d.containsKey("box") &&
          (d["box"] is List) &&
          (d["box"].length >= 5)) {
        int clsValue = int.tryParse(d["cls"][0].toString()) ?? -1;
        double conf = double.tryParse(d["box"][0].toString()) ?? 0.0;
        return clsValue == 74 && conf >= confidenceThreshold;
      }
      return false;
    }).toList();

    // If no book is detected, speak "no book" if a certain time has passed.
    if (bookDetections.isEmpty) {
      if (DateTime.now().difference(lastDetectionTime).inSeconds >
              noDetectionThreshold &&
          DateTime.now().difference(lastInstructionTime).inSeconds >=
              instructionCooldown) {
        speak("ไม่เห็นหนังสือ, no book");
        lastInstructionTime = DateTime.now();
        currentState = "no book";
      }
      return;
    }

    // Update detection time.
    lastDetectionTime = DateTime.now();

    // Use the first valid detection (or choose the best among them).
    final detection = bookDetections.first;

    // Convert detection coordinates into screen coordinates.
    double factorX =
        screenSize.width / (cameraImage?.height ?? screenSize.width);
    double factorY =
        screenSize.height / (cameraImage?.width ?? screenSize.height);

    double x1 = detection["box"][0] * factorX;
    double y1 = detection["box"][1] * factorY;
    double x2 = detection["box"][2] * factorX;
    double y2 = detection["box"][3] * factorY;
    double boxWidth = x2 - x1;
    double boxHeight = y2 - y1;
    double boxCenterX = x1 + boxWidth / 2;
    double boxCenterY = y1 + boxHeight / 2;

    double screenCenterX = screenSize.width / 2;
    double screenCenterY = screenSize.height / 2;

    // Define the "optimal" (target) box.
    double optimalWidth = screenSize.width * widthCoverage;
    double optimalHeight = screenSize.height * heightCoverage;
    double optX1 = (screenSize.width - optimalWidth) / 2;
    double optY1 = (screenSize.height - optimalHeight) / 2;

    // Set dynamic offset thresholds.
    double dynamicOffsetThresholdX = screenSize.width * 0.04;
    double dynamicOffsetThresholdY = screenSize.height * 0.04;
    double minBoxSize = optimalWidth * 0.7;
    double maxBoxSize = optimalWidth * 1.3;

    // Determine the state based on the box's size and position relative to the optimal area.
    String newState;
    if (boxWidth < minBoxSize || boxHeight < optimalHeight * 0.7) {
      newState = "closer";
    } else if (boxWidth > maxBoxSize || boxHeight > optimalHeight * 1.3) {
      newState = "further";
    } else if ((boxCenterX - screenCenterX).abs() > dynamicOffsetThresholdX) {
      // If the detection is off-center horizontally.
      newState = (boxCenterX - screenCenterX) > 0 ? "left" : "right";
    } else if ((boxCenterY - screenCenterY).abs() > dynamicOffsetThresholdY) {
      newState = (boxCenterY - screenCenterY) > 0 ? "down" : "up";
    } else {
      newState = "perfect";
    }

    // Issue TTS instruction only if the state has changed and the cooldown has passed.
    if (newState != currentState &&
        DateTime.now().difference(lastInstructionTime).inSeconds >=
            instructionCooldown) {
      final Map<String, String> instructions = {
        "perfect": "สมบูรณ์แบบ, perfect",
        "left": "เลื่อนซ้าย, left",
        "right": "เลื่อนขวา, right",
        "up": "เลื่อนขึ้น, up",
        "down": "เลื่อนลง, down",
        "closer": "เข้าใกล้มากขึ้น, closer",
        "further": "ถอยออกไป, further",
        "no book": "ไม่เห็นหนังสือ, no book",
      };
      speak(instructions[newState] ?? newState);
      currentState = newState;
      lastInstructionTime = DateTime.now();
    }
  }

  Future<void> speak(String text) async {
    await flutterTts.setLanguage("th-TH");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak(text);
  }

  /// This method overlays bounding boxes for detected objects.
  List<Widget> displayBoxes(Size screen) {
    if (yoloResults.isEmpty || cameraImage == null) return [];

    double factorX = screen.width / (cameraImage?.height ?? 1);
    double factorY = screen.height / (cameraImage?.width ?? 1);

    return yoloResults.map((result) {
      double x1 = result["box"][0] * factorX;
      double y1 = result["box"][1] * factorY;
      double boxWidth = (result["box"][2] - result["box"][0]) * factorX;
      double boxHeight = (result["box"][3] - result["box"][1]) * factorY;

      if (!result.containsKey("cls") ||
          !(result["cls"] is List) ||
          result["cls"].isEmpty ||
          int.tryParse(result["cls"][0].toString()) != 74) {
        return Container();
      }

      return Positioned(
        left: x1,
        top: y1,
        width: boxWidth,
        height: boxHeight,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
        ),
      );
    }).toList();
  }

  Widget buildOptimalBoxOverlay(Size screen) {
    double optimalWidth = screen.width * widthCoverage;
    double optimalHeight = screen.height * heightCoverage;
    double x1 = (screen.width - optimalWidth) / 2;
    double y1 = (screen.height - optimalHeight) / 2;

    return Positioned(
      left: x1,
      top: y1,
      width: optimalWidth,
      height: optimalHeight,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.green, width: 2.0),
        ),
        /*
        child: Center(
          child: CustomPaint(
            painter: CrosshairPainter(),
            size: Size(optimalWidth, optimalHeight),
          ),
        ),*/
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.of(context).size;

    if (cameras.isEmpty) {
      return const Scaffold();
    }

    return Scaffold(
      body: _screenSize == Size.zero
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                buildOptimalBoxOverlay(_screenSize),
                ...displayBoxes(_screenSize),
              ],
            ),
    );
  }
}


/*
/// A simple custom painter to draw crosshair lines at the center.
class CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2;

    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    final double markerSize = 20;

    // Horizontal line
    canvas.drawLine(Offset(centerX - markerSize, centerY),
        Offset(centerX + markerSize, centerY), paint);
    // Vertical line
    canvas.drawLine(Offset(centerX, centerY - markerSize),
        Offset(centerX, centerY + markerSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
*/