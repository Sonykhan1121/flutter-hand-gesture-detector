import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../constants/colors.dart';
import '../global_context.dart';

class DSnackBar {
  DSnackBar._();

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _currentSnackBar;
  static ScaffoldMessengerState? _currentMessenger;

  static void successSnackBar({
    required String title,
    String message = '',
    String? name,
    int duration = 3,
    int icon = 1,
    BuildContext? context,
  }) {
    _showSnackBar(
      context: context,
      name: name,
      title: title,
      message: message,
      duration: duration,
      icon: icon == 1 ? Iconsax.check : null,
      strokeColor: DColors.sSuccessStroke,
      backgroundColor: DColors.sSuccessBackground,
    );
  }

  static void informationSnackBar({
    required String title,
    String message = '',
    int duration = 3,
    BuildContext? context,
  }) {
    _showSnackBar(
      context: context,
      title: title,
      message: message,
      duration: duration,
      icon: Iconsax.warning_2,
      strokeColor: DColors.sInfoStroke,
      backgroundColor: DColors.sInfoBackground,
    );
  }

  static void errorSnackBar({
    required String title,
    String message = '',
    int duration = 3,
    BuildContext? context,
  }) {
    _showSnackBar(
      context: context,
      title: title,
      message: message,
      duration: duration,
      icon: Icons.error,
      strokeColor: DColors.sErrorStroke,
      backgroundColor: DColors.sErrorBackground,
    );
  }

  static void _showSnackBar({
    required String title,
    required String message,
    required int duration,
    required Color strokeColor,
    required Color backgroundColor,
    BuildContext? context,
    String? name,
    IconData? icon,
  }) {
    final resolvedContext = context ?? GlobalContext.context;
    if (resolvedContext == null) {
      debugPrint('No context available for SnackBar!');
      return;
    }

    final messenger = ScaffoldMessenger.of(resolvedContext);
    if (_currentSnackBar != null) {
      if (identical(_currentMessenger, messenger)) return;
      _currentSnackBar = null;
      _currentMessenger = null;
    }

    final snackBar = SnackBar(
      elevation: 0,
      duration: Duration(seconds: duration),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(20),
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: strokeColor),
      ),
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: strokeColor),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    if (name != null && name.isNotEmpty)
                      Text(
                        name,
                        style: Theme.of(resolvedContext).textTheme.bodyLarge!
                            .copyWith(
                              color: DColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    Text(
                      title,
                      style: Theme.of(
                        resolvedContext,
                      ).textTheme.bodyLarge!.copyWith(color: strokeColor),
                    ),
                  ],
                ),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: Theme.of(
                      resolvedContext,
                    ).textTheme.bodyMedium!.copyWith(color: strokeColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final controller = messenger.showSnackBar(snackBar);
    _currentSnackBar = controller;
    _currentMessenger = messenger;
    controller.closed.whenComplete(() {
      if (identical(_currentSnackBar, controller)) {
        _currentSnackBar = null;
        _currentMessenger = null;
      }
    });
  }
}
