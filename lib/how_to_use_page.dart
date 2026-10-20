// Task 113: экран «Как пользоваться» — открывается по тапу на баннер
// бесплатного лимита на главном экране. Объясняет модель: что бесплатно,
// что даёт подписка, что остаётся приватным.
import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'services/usage_limit_service.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';

class HowToUsePage extends StatelessWidget {
  const HowToUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DictaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Text(AppStrings.t('help_title', context),
                  style: Theme.of(context).textTheme.headlineMedium),
            ]),
            const SizedBox(height: 16),

            // Что делает приложение
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.howtoWhatTitle(context),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(AppStrings.howtoWhatBody(context),
                      style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.6)),
                ],
              ),
            ),

            // Что бесплатно
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.howtoFreeTitle(context),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.howtoFreeBody(context,
                        limit: UsageLimitService.dailyMinutesLimit),
                    style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.6),
                  ),
                ],
              ),
            ),

            // Что даёт подписка
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.howtoSubTitle(context),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(AppStrings.howtoSubBody(context),
                      style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.6)),
                ],
              ),
            ),

            // Приватность
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.howtoPrivacyTitle(context),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(AppStrings.howtoPrivacyBody(context),
                      style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.6)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
