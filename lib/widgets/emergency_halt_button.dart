import 'package:flutter/material.dart';
import '../services/task_executor.dart';

class EmergencyHaltButton extends StatelessWidget {
  const EmergencyHaltButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      backgroundColor: Colors.red,
      tooltip: 'Emergency Halt',
      onPressed: () {
        TaskExecutor.isHalted = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency Halt Triggered! Stopping loop...')),
        );
      },
      child: const Icon(Icons.stop, color: Colors.white),
    );
  }
}
