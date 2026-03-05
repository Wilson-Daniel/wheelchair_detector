// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs, use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:wheelchair_movement_detector/wheelchair_movement_detector.dart';

import 'WheelchairMovementDetector.dart';

// import 'snake.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
    [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensors Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0x9f4376f8),
      ),
      home: const WheelchairMovementScreen(),
    );
  }
}

class WheelchairMovementScreen extends StatefulWidget {
  const WheelchairMovementScreen({Key? key}) : super(key: key);

  @override
  State<WheelchairMovementScreen> createState() => _WheelchairMovementScreenState();
}

class _WheelchairMovementScreenState extends State<WheelchairMovementScreen> {
  final MovementDetector _detector = MovementDetector();
  MovementData? _currentData;
  List<MovementData> allOverData = [];

  @override
  void initState() {
    super.initState();
    _initializeDetector();
  }

  Future<void> _initializeDetector() async {
    await _detector.initialize();

    // Listen to movement data updates
    _detector.movementDataStream.listen((data) {
      setState(() {
        _currentData = data;
        allOverData.add(data);
      });
    });
  }

  @override
  void dispose() {
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentData == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.grey,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_backup_restore),
            onPressed: () {
              allOverData.forEach((value){
                print("value ${value.totalDistance}");
              });
              _detector.resetSession();
            },
            tooltip: 'Reset Session',
          ),
        ],
      ),
      body: _currentData!.isCalibrating
          ? _buildCalibrationView()
          : _buildMainView(),
    );
  }

  Widget _buildCalibrationView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text(
            'Calibrating sensors...',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            'Keep device still',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    final data = _currentData!;
    final sessionDuration = data.getSessionDuration();
    final currentMovingTime = data.getCurrentMovingTime();
    final avgSpeed = _detector.calculateAverageSpeed();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Movement Status
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: data.isMoving
                      ? [Colors.green.shade400, Colors.green.shade600]
                      : [Colors.grey.shade300, Colors.grey.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    data.isMoving ? Icons.accessible : Icons.accessibility_new,
                    size: 60,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    data.movementType,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Session Distance (Main Display)
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.straighten, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'Session Distance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    MovementFormatters.formatDistance(data.sessionDistance),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // Stats Grid
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Current Speed',
                    MovementFormatters.formatVelocityKmh(data.velocity),
                    MovementFormatters.formatVelocityMs(data.velocity),
                    Icons.speed,
                    Colors.black54,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'Avg Speed',
                    MovementFormatters.formatVelocityKmh(avgSpeed),
                    MovementFormatters.formatVelocityMs(avgSpeed),
                    Icons.av_timer,
                    Colors.black54,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Moving Time',
                    MovementFormatters.formatDuration(currentMovingTime),
                    'Active',
                    Icons.timer,
                    Colors.black54,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'Session Time',
                    MovementFormatters.formatDuration(sessionDuration),
                    'Total',
                    Icons.access_time,
                    Colors.black54,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String title,
      String value,
      String subtitle,
      IconData icon,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}