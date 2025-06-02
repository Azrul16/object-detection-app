import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Delivery Bot Controller', home: HomeScreen());
  }
}

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BluetoothConnection? connection;
  late CameraController _cameraController;
  late ObjectDetector _objectDetector;
  bool _isDetecting = false;
  Position? currentPosition;
  bool _objectFound = false;

  @override
  void initState() {
    super.initState();
    initBluetooth();
    initCamera();
    initGPS();

    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        classifyObjects: true,
        multipleObjects: true,
        mode: DetectionMode.stream,
      ),
    );
  }

  void initBluetooth() async {
    List<BluetoothDevice> devices =
        await FlutterBluetoothSerial.instance.getBondedDevices();
    if (devices.isNotEmpty) {
      BluetoothConnection.toAddress(devices.first.address)
          .then((conn) {
            connection = conn;
            print("Connected to Raspberry Pi via Bluetooth");
          })
          .catchError((error) {
            print("Bluetooth connection error: $error");
          });
    }
  }

  void initGPS() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream().listen((pos) {
      setState(() {
        currentPosition = pos;
      });
    });
  }

  void initCamera() async {
    _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await _cameraController.initialize();

    _cameraController.startImageStream((CameraImage image) async {
      if (_isDetecting || connection == null || currentPosition == null) return;
      _isDetecting = true;

      try {
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();
        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );

        final detectedObjects = await _objectDetector.processImage(inputImage);
        final labels =
            detectedObjects
                .where((obj) => obj.labels.isNotEmpty)
                .map((obj) => obj.labels.first.text)
                .toList();

        setState(() {
          _objectFound = labels.isNotEmpty;
        });

        final data = {
          'gps': {
            'lat': currentPosition!.latitude,
            'lon': currentPosition!.longitude,
          },
          'objects': labels,
        };

        connection!.output.add(
          Uint8List.fromList(utf8.encode(jsonEncode(data) + "\n")),
        );
        await connection!.output.allSent;
      } catch (e) {
        print("Detection error: $e");
      }

      _isDetecting = false;
    });

    setState(() {});
  }

  @override
  void dispose() {
    _cameraController.dispose();
    connection?.dispose();
    _objectDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Delivery Bot Control')),
      body:
          _cameraController.value.isInitialized
              ? Stack(
                children: [
                  CameraPreview(_cameraController),
                  Positioned(
                    bottom: 30,
                    left: 20,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentPosition != null
                                ? 'Lat: ${currentPosition!.latitude.toStringAsFixed(6)}\nLon: ${currentPosition!.longitude.toStringAsFixed(6)}'
                                : 'Getting location...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _objectFound
                                ? '🎯 Object Detected'
                                : '🔍 No Object',
                            style: TextStyle(
                              color: _objectFound ? Colors.green : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
              : Center(child: CircularProgressIndicator()),
    );
  }
}
