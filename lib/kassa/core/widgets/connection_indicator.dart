import 'package:flutter/material.dart';
import '../services/wss_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: WssService().connectionStream,
      initialData: WssService().isConnected,
      builder: (context, snapshot) {
        final connected = snapshot.data ?? false;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? Colors.green : Colors.red,
          ),
        );
      },
    );
  }
}

/// Qaysi serverda ishlayotganini ko'rsatuvchi belgi.
///
/// ONLINE holati kassir uchun muhim ogohlantirish: cloud restoran ichidagi
/// printerga yeta olmaydi, oshxona cheki local ko'tarilgach chiqadi.
class EndpointBadge extends StatelessWidget {
  const EndpointBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ApiService().endpointStream,
      initialData: ApiService().isUsingCloud,
      builder: (context, snapshot) {
        final onCloud = snapshot.data ?? false;
        if (!onCloud && !ApiService().hasCloud) return const SizedBox.shrink();
        final color = onCloud ? AppColors.warning : AppColors.success;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: onCloud ? AppColors.warningSoft : AppColors.successSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                onCloud ? Icons.cloud_rounded : Icons.lan_rounded,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                onCloud ? 'ONLINE' : 'LOCAL',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
