import 'package:flutter/material.dart';

import '../../../core/widgets/tutorial_widgets.dart';
import '../widgets/admin_page.dart';

/// Admin panelidagi «Video qo'llanma» bo'limi — barcha videolar bitta joyda.
class AdminTutorialsPage extends StatelessWidget {
  const AdminTutorialsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPage(
      subtitle: 'Bosing — video yuklanadi va ochiladi',
      padded: false,
      child: TutorialsList(),
    );
  }
}
