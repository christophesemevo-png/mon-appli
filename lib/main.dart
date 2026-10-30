import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

void main() => runApp(const MonAppli());

class MonAppli extends StatelessWidget {
  const MonAppli({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mon Appli',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const Accueil(),
    );
  }
}

const textExt = {
  'txt', 'md', 'csv', 'json', 'xml', 'html', 'css', 'js', 'py', 'log', 'ini', 'yml', 'yaml'
};

class Accueil extends StatefulWidget {
  const Accueil({super.key});

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  String? nom;
  final ctrl = TextEditingController();

  Future<void> ouvrir() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.single.path == null) return;
    final f = r.files.single;
    final chemin = f.path!;
    final ext = (f.extension ?? '').toLowerCase();
    if (textExt.contains(ext)) {
      final octets = await File(chemin).readAsBytes();
      setState(() {
        nom = f.name;
        ctrl.text = utf8.decode(octets, allowMalformed: true);
      });
    } else {
      await OpenFilex.open(chemin);
    }
  }

  Future<void> enregistrer() async {
    final octets = Uint8List.fromList(utf8.encode(ctrl.text));
    final res = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer le fichier',
      fileName: nom,
      bytes: octets,
    );
    if (!mounted) return;
    if (res != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Fichier enregistré')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(nom ?? 'Mon Appli'),
        actions: [
          if (nom != null)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Enregistrer',
              onPressed: enregistrer,
            ),
        ],
      ),
      body: nom == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Appuie sur « Ouvrir un fichier » pour commencer.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: ctrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: ouvrir,
        icon: const Icon(Icons.folder_open),
        label: const Text('Ouvrir un fichier'),
      ),
    );
  }
}
