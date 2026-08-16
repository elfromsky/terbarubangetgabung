import 'package:flutter/material.dart';

class Appbar extends StatelessWidget {
  const Appbar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _logoimage(1),
          Flexible(
            child: Text(
              "Elang Smart Home",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _logoimage(2),
        ],
      ),
    );
  }

  Widget _logoimage(int logo) {
    if (logo == 1) {
      return Image.asset("images/logo1.jpg", width: 70, height: 80);
    } else {
      return Image.asset("images/logo2.jpg", width: 70, height: 80);
    }
  }
}
