# Relay Controller App

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.x-blue?logo=dart)
![Platform](https://img.shields.io/badge/Platform-Android-success)
![GitHub](https://img.shields.io/badge/Git-Version%20Control-black?logo=github)

A modern Flutter application developed during my internship for controlling smart appliances over a local network. The application communicates with a backend server and embedded hardware to discover devices, control relays, execute scenes, manage PWM outputs, and configure connected hardware.

---
## 📥 Download APK

[![Download APK](https://img.shields.io/badge/Download-Android%20APK-brightgreen?logo=android)](https://github.com/Akashv-deve/relay-controller-app/releases/latest)

> Download the latest stable Android release of Relay Controller from GitHub Releases.

# Preview

![](images/dashboard_dark.jpg)

---

# Features

- Automatic Hub Discovery using UDP Broadcast
- Manual Hub Connection using IP Address
- Smart Relay Control
- PWM Brightness / Fan Speed Control
- Analog Output Monitoring
- Scene Execution and Management
- Dark & Light Theme Support
- Password Protected Settings
- Persistent Hub Connection using Local Storage
- Responsive Material Design UI
- Smooth Animations and Error Handling

---

# Tech Stack

- Flutter
- Dart
- REST API
- UDP Broadcast Discovery
- SharedPreferences
- Material Design
- Stateful Widgets
- Git
- GitHub

---

# Architecture

```text
Flutter App
      │
      ▼
REST API / UDP
      │
      ▼
Backend Server
      │
      ▼
Microcontroller
      │
      ▼
Relay Hardware
```

---

# Project Structure

```text
lib/
│
├── models/
│   ├── smart_device.dart
│   └── smart_scene.dart
│
├── services/
│   ├── hub_service.dart
│   └── udp_broadcast_listener.dart
│
├── themes/
│   └── app_theme.dart
│
└── main.dart
```

---

# Screenshots

## Network Discovery

| Light Theme | Dark Theme |
|-------------|------------|
| ![](images/network_discovery_light.jpg) | ![](images/network_discovery_dark.jpg) |

---

## Dashboard

| Light Theme | Dark Theme |
|-------------|------------|
| ![](images/dashboard_light.jpg) | ![](images/dashboard_dark.jpg) |

---

## Scene Management

| Meeting Scene | AV Room Scene |
|---------------|---------------|
| ![](images/scene_meeting.jpg) | ![](images/scene_avroom.jpg) |

---

## PWM Live Control

| 55% Output | 30% Output |
|-------------|------------|
| ![](images/pwm_control_55.jpg) | ![](images/pwm_control_30.jpg) |

---

## Output State Control

| Power Output | TV Output |
|--------------|-----------|
| ![](images/state_control_power.jpg) | ![](images/state_control_tv.jpg) |

---

## Hub Management

![](images/hub_management.jpg)

---

# Installation

```bash
git clone https://github.com/Akashv-deve/RelayController.git

cd RelayController

flutter pub get

flutter run
```

---

# Future Improvements

- MQTT Support
- Voice Assistant Integration
- Offline Device Synchronization
- Multi-Room Management
- Improved Modular Architecture
- User Authentication

---

# Disclaimer

This repository contains only the Flutter frontend application developed during my internship.

The backend server, embedded firmware, hardware design, and device firmware were developed separately as part of the internship environment and are therefore not included in this repository.
