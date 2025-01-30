
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

//import 'package:tflite/tflite.dart';
//import 'dart:async';
//import 'dart:math';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late CameraController controller;
  List<CameraDescription> cameras = [];
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  bool _isFlashOn = false;
  bool _isFromCameraRoll = true;

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  Future<void> initializeCamera() async {
    try {
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
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> toggleFlash() async {
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
    await controller.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
  }

  Future<void> captureImage() async {
    _isFromCameraRoll = false;
    if (!controller.value.isInitialized) {
      return;
    }
  }

  void _handleZoomStart(ScaleStartDetails details) {
    _baseZoomLevel = _currentZoomLevel;
  }

  void _handleZoomUpdate(ScaleUpdateDetails details) {
    setState(() {
      _currentZoomLevel = (_baseZoomLevel * details.scale).clamp(1.0, 8.0);
    });
    controller.setZoomLevel(_currentZoomLevel);
  }

  @override
  Widget build(BuildContext context) {
    if (cameras.isEmpty) {
      return const Scaffold();
    }

    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: SizedBox(
            width: 90,
            height: 90,
            child: ElevatedButton(
              onPressed: () {
                 
              },
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
              ),
              child: Semantics(
                label: 'ย้อนกลับไปหน้าสแกน',
                child: const Center(child: Icon(Icons.arrow_back))),
            ),
          ),
          actions: [
            IconButton(
                icon: Semantics(
                  label: 'เปิดไฟแฟลช',
                  child: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off)),
                onPressed: toggleFlash,
                color: Colors.white,
              ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _handleZoomStart,
                onScaleUpdate: _handleZoomUpdate,
                child: controller.value.isInitialized
                    ? CameraPreview(controller)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: SizedBox(
                width: 80,
                height: 80,
                child: Material(
                  type: MaterialType.transparency,
                  child: Semantics(
                    label: 'ถ่ายรูป',
                    child: Ink(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 5),
                        color: const Color.fromARGB(234, 255, 255, 255),
                        shape: BoxShape.circle,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(1000),
                        onTap: () {
                          captureImage();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}