import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 팝업(AlertDialog) 내용 폭: 원하는 폭과 "화면 폭 - 48" 중 작은 쪽 (폰에서 잘리지 않게, 82차)
double adminDialogWidth(BuildContext context, double wanted) =>
    math.min(wanted, MediaQuery.sizeOf(context).width - 48);
