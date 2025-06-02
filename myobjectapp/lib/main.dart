import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Delivery Bot Controller',
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BluetoothConnection? connection;
  Position? currentPosition;
  Timer? gpsUpdateTimer;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    requestPermissions().then((granted) {
      setState(() {
        _permissionsGranted = granted;
      });
      if (granted) {
        initBluetooth();
        initGPS();
      } else {
        print("Required permissions not granted!");
      }
    });
  }

  @override
  void dispose() {
    connection?.dispose();
    gpsUpdateTimer?.cancel();
    super.dispose();
  }

  Future<bool> requestPermissions() async {
    final locationStatus = await Permission.locationWhenInUse.request();
    final bluetoothScanStatus = await Permission.bluetoothScan.request();
    final bluetoothConnectStatus = await Permission.bluetoothConnect.request();

    return locationStatus.isGranted &&
        bluetoothScanStatus.isGranted &&
        bluetoothConnectStatus.isGranted;
  }

  void initBluetooth() async {
    List<BluetoothDevice> devices =
        await FlutterBluetoothSerial.instance.getBondedDevices();

    if (devices.isNotEmpty) {
      try {
        connection = await BluetoothConnection.toAddress(devices.first.address);
        print("Connected to Raspberry Pi via Bluetooth");
      } catch (e) {
        print("Cannot connect to Bluetooth device: $e");
      }
    } else {
      print("No bonded Bluetooth devices found.");
    }
  }

  void initGPS() {
    gpsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        if (connection != null && connection!.isConnected) {
          final data = {'lat': pos.latitude, 'lon': pos.longitude};

          connection!.output.add(
            Uint8List.fromList(utf8.encode(jsonEncode(data) + "\n")),
          );
          await connection!.output.allSent;
        }

        setState(() {
          currentPosition = pos;
        });
      } catch (e) {
        print("Error getting GPS position: $e");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Bot Control'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Container(
        color: Colors.black87,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child:
            !_permissionsGranted
                ? const Center(
                  child: Text(
                    'Waiting for permissions...',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                )
                : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      currentPosition != null
                          ? 'Latitude: ${currentPosition!.latitude.toStringAsFixed(6)}\nLongitude: ${currentPosition!.longitude.toStringAsFixed(6)}'
                          : 'Getting GPS location...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 22),
                    ),
                    const SizedBox(height: 20),
                    // Text(
                    //   connection != null && connection!.isConnected
                    //       ? 'Bluetooth: Connected'
                    //       : 'Bluetooth: Disconnected',
                    //   style: TextStyle(
                    //     color:
                    //         connection != null && connection!.isConnected
                    //             ? Colors.green
                    //             : Colors.red,
                    //     fontSize: 18,
                    //   ),
                    // ),
                  ],
                ),
      ),
    );
  }
}
