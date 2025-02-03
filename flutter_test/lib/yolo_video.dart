/*
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite/tflite.dart';
import 'dart:async';
import 'dart:math';

List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter YOLO Detection',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DetectionPage(),
    );
  }
}

class DetectionPage extends StatefulWidget {
  const DetectionPage({Key? key}) : super(key: key);

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  CameraController? _cameraController;
  bool _isDetecting = false;

  // TTS
  final FlutterTts flutterTts = FlutterTts();
  DateTime _lastInstructionTime = DateTime.now();
  Duration instructionCooldown = const Duration(seconds: 3);
  String? currentState;

  // Inference Results
  List<dynamic> _recognitions = [];
  double _imageWidth = 0;
  double _imageHeight = 0;

  // Frame skipping
  int frameSkip = 10;
  int frameCount = 0;

  // Book detection info
  DateTime _lastDetectionTime = DateTime.now();
  Duration noDetectionThreshold = const Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadModel();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (cameras == null || cameras!.isEmpty) {
      // Handle no camera found scenario
      return;
    }
    _cameraController = CameraController(
      cameras![0],
      ResolutionPreset.medium, // or high, but medium is faster
      enableAudio: false,
    );
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() {});

    // Start streaming frames
    _cameraController!.startImageStream((CameraImage img) {
      if (!_isDetecting && frameCount % frameSkip == 0) {
        _isDetecting = true;
        _runDetectionOnFrame(img).then((_) {
          _isDetecting = false;
        });
      }
      frameCount++;
    });
  }

  Future<void> _loadModel() async {
    try {
      String? res = await Tflite.loadModel(
        model: "assets/model.tflite",
        labels: "assets/labels.txt",
        numThreads: 1, // Increase if you have multiple cores
      );
      debugPrint("Model loaded: $res");
    } catch (e) {
      debugPrint("Failed to load model: $e");
    }
  }

  Future<void> _runDetectionOnFrame(CameraImage cameraImage) async {
    // Convert the CameraImage to the input type expected by your TFLite function.
    // For YOLO in many Tflite examples, you’d do something like:
    List<dynamic>? recognitions = await Tflite.detectObjectOnFrame(
      bytesList: cameraImage.planes.map((plane) {
        return plane.bytes;
      }).toList(),
      imageHeight: cameraImage.height,
      imageWidth: cameraImage.width,
      imageMean: 0.0,
      imageStd: 255.0,
      threshold: 0.3, // confidence threshold
      numResultsPerClass: 2,
      asynch: true,
      // model defaults will vary depending on YOLO version. Adjust as needed.
    );

    if (!mounted || recognitions == null) return;

    setState(() {
      _recognitions = recognitions;
      _imageWidth = cameraImage.width.toDouble();
      _imageHeight = cameraImage.height.toDouble();
    });

    _handleDetections(recognitions);
  }

  void _handleDetections(List<dynamic> recognitions) {
    // Filter for book detection. In your labels.txt, assume "book" is a certain label.
    // The TFLite plugin often returns results as:
    // {
    //   "confidenceInClass": 0.85,
    //   "detectedClass": "book",
    //   "rect": {"x":0.1,"y":0.2,"w":0.3,"h":0.4}
    // }
    bool bookDetected = false;
    double highestConfidence = 0.0;
    Map<String, dynamic>? bestBox;

    for (final result in recognitions) {
      final detectedClass = result["detectedClass"];
      final confidence = (result["confidenceInClass"] as double);
      if (detectedClass == "book" && confidence >= 0.3) {
        bookDetected = true;
        if (confidence > highestConfidence) {
          highestConfidence = confidence;
          bestBox = result;
        }
      }
    }

    if (bookDetected) {
      _lastDetectionTime = DateTime.now();
      _checkPositionAndSpeak(bestBox);
    } else {
      // If no book detected for over threshold, speak "no book"
      if (DateTime.now().difference(_lastDetectionTime) > noDetectionThreshold) {
        _speakOnce("ไม่เห็นหนังสือ, no book");
      }
    }
  }

  /// Checks bounding box position relative to center, size, etc. Then speaks instructions if needed.
  void _checkPositionAndSpeak(Map<String, dynamic>? boxData) {
    if (boxData == null) return;

    // Extract bounding box info
    final rect = boxData["rect"]; // {x, y, w, h}, usually in [0,1] normalized
    final double x = rect["x"];
    final double y = rect["y"];
    final double w = rect["w"];
    final double h = rect["h"];

    // Convert normalized coords to actual pixel values if needed
    final double boxCenterX = (x + w / 2);
    final double boxCenterY = (y + h / 2);

    // Let's define thresholds just like the Python version
    // Because rect is normalized, you can define your thresholds in normalized terms
    const double offsetThreshold = 0.05;
    const double minBoxWidth = 0.2;  // example
    const double maxBoxWidth = 0.6;  // example

    String newState;
    // Check size first (similar logic to your Python code)
    if (w < minBoxWidth) {
      newState = "closer";
    } else if (w > maxBoxWidth) {
      newState = "further";
    } else if ((boxCenterX - 0.5).abs() > offsetThreshold) {
      // Book is left or right of center
      newState = (boxCenterX > 0.5) ? "left" : "right";
    } else if ((boxCenterY - 0.5).abs() > offsetThreshold) {
      // Book is above or below center
      newState = (boxCenterY > 0.5) ? "down" : "up";
    } else {
      newState = "perfect";
    }

    // Speak instructions if new state and cooldown passed
    if (newState != currentState &&
        DateTime.now().difference(_lastInstructionTime) > instructionCooldown) {
      currentState = newState;
      _lastInstructionTime = DateTime.now();

      final instructions = {
        "perfect": "สมบูรณ์แบบ, perfect",
        "left": "เลื่อนซ้าย, left",
        "right": "เลื่อนขวา, right",
        "up": "เลื่อนขึ้น, up",
        "down": "เลื่อนลง, down",
        "closer": "เข้าใกล้มากขึ้น, closer",
        "further": "ถอยออกไป, further",
      };

      _speakOnce(instructions[newState]!);
    }
  }

  /// Only speak a phrase once (non-blocking).
  void _speakOnce(String text) async {
    await flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final size = MediaQuery.of(context).size;
    final scale =
        _cameraController!.value.aspectRatio / (size.width / size.height);

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter YOLO Book Detection')),
      body: Stack(
        children: [
          // Camera Preview
          Transform.scale(
            scale: scale,
            child: Center(
              child: CameraPreview(_cameraController!),
            ),
          ),
          // Bounding Boxes Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: DetectionPainter(
                recognitions: _recognitions,
                previewH: _imageHeight,
                previewW: _imageWidth,
                screenH: size.height,
                screenW: size.width,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A CustomPainter that draws bounding boxes onto the screen.
class DetectionPainter extends CustomPainter {
  final List<dynamic> recognitions;
  final double previewW;
  final double previewH;
  final double screenW;
  final double screenH;

  DetectionPainter({
    required this.recognitions,
    required this.previewW,
    required this.previewH,
    required this.screenW,
    required this.screenH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.pink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (var re in recognitions) {
      if (re["rect"] == null) continue;
      double x = re["rect"]["x"];
      double w = re["rect"]["w"];
      double y = re["rect"]["y"];
      double h = re["rect"]["h"];
      // The TFLite plugin usually gives normalized bounding boxes [0..1]
      // Convert them to actual coordinates:
      final left = x * screenW;
      final top = y * screenH;
      final width = w * screenW;
      final height = h * screenH;

      Rect rect = Rect.fromLTWH(left, top, width, height);
      canvas.drawRect(rect, paint);

      // Draw label text
      final textSpan = TextSpan(
        text:
            "${re["detectedClass"]} ${(re["confidenceInClass"] * 100).toStringAsFixed(0)}%",
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter =
          TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(left, top - 20));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return true;
  }
}
*/

import 'package:flutter_vision/flutter_vision.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

late List<CameraDescription> cameras;

class YoloVideo extends StatefulWidget {
  const YoloVideo({Key? key}) : super(key: key);

  @override
  State<YoloVideo> createState() => _YoloVideoState();
}

class _YoloVideoState extends State<YoloVideo> {
  late CameraController controller;
  late FlutterVision vision;
  late List<Map<String, dynamic>> yoloResults;

  CameraImage? cameraImage;
  bool isLoaded = false;
  bool isDetecting = false;
  double confidenceThreshold = 0.5;

  @override
  void initState() {
    super.initState();
    init();
  }

  init() async {
    cameras = await availableCameras();
    vision = FlutterVision();
    controller = CameraController(cameras[0], ResolutionPreset.high);
    controller.initialize().then((value) {
      loadYoloModel().then((value) {
        setState(() {
          isLoaded = true;
          isDetecting = false;
          yoloResults = [];
        });
      });
    });
  }

  @override
  void dispose() async {
    super.dispose();
    controller.dispose();
    await vision.closeYoloModel();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    if (!isLoaded) {
      return const Scaffold(
        body: Center(
          child: Text("Model not loaded, waiting for it"),
        ),
      );
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(
              controller,
            ),
          ),
          ...displayBoxesAroundRecognizedObjects(size),
          Positioned(
            bottom: 75,
            width: MediaQuery.of(context).size.width,
            child: Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    width: 5, color: Colors.white, style: BorderStyle.solid),
              ),
              child: isDetecting
                  ? IconButton(
                      onPressed: () async {
                        stopDetection();
                      },
                      icon: const Icon(
                        Icons.stop,
                        color: Colors.red,
                      ),
                      iconSize: 50,
                    )
                  : IconButton(
                      onPressed: () async {
                        await startDetection();
                      },
                      icon: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                      ),
                      iconSize: 50,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> loadYoloModel() async {
    await vision.loadYoloModel(
        labels: 'assets/coco-labels-2014_2017.txt',
        modelPath: 'assets/yolov8n_float32.tflite',
        modelVersion: "yolov8",
        numThreads: 1,
        useGpu: true);
    setState(() {
      isLoaded = true;
    });
  }

// Real-time object detection function by yoloOnFrame
  Future<void> yoloOnFrame(CameraImage cameraImage) async {
    final result = await vision.yoloOnFrame(
        bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
        imageHeight: cameraImage.height,
        imageWidth: cameraImage.width,
        iouThreshold: 0.4,
        confThreshold: 0.4,
        classThreshold: 0.5);
    if (result.isNotEmpty) {
      setState(() {
        yoloResults = result;
      });
    }
  }

  Future<void> startDetection() async {
    setState(() {
      isDetecting = true;
    });
    if (controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream((image) async {
      if (isDetecting) {
        cameraImage = image;
        yoloOnFrame(image);
      }
    });
  }

  Future<void> stopDetection() async {
    setState(() {
      isDetecting = false;
      yoloResults.clear();
    });
  }

  List<Widget> displayBoxesAroundRecognizedObjects(Size screen) {
    if (yoloResults.isEmpty) return [];
    double factorX = screen.width / (cameraImage?.height ?? 1);
    double factorY = screen.height / (cameraImage?.width ?? 1);
    Color colorPick = const Color.fromARGB(255, 50, 233, 30);

    return yoloResults.map((result) {
      double objectX = result["box"][0] * factorX;
      double objectY = result["box"][1] * factorY;
      double objectWidth = (result["box"][2] - result["box"][0]) * factorX;
      double objectHeight = (result["box"][3] - result["box"][1]) * factorY;
      return Positioned(
        left: objectX,
        top: objectY,
        width: objectWidth,
        height: objectHeight,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
          child: Text(
            "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = colorPick,
              color: Color.fromARGB(255, 115, 0, 255),
              fontSize: 18.0,
            ),
          ),
        ),
      );
    }).toList();
  }
}
