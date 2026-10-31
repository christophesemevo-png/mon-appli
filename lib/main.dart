import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
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

String lettre(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

class Accueil extends StatefulWidget {
  const Accueil({super.key});

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  String? nom;
  String mode = '';
  final ctrl = TextEditingController();
  xl.Excel? classeur;
  String? feuille;
  int lignes = 10;
  int colonnes = 5;

  void message(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> ouvrir() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.single.path == null) return;
    final f = r.files.single;
    final chemin = f.path!;
    final ext = (f.extension ?? '').toLowerCase();
    if (ext == 'xlsx') {
      try {
        final octets = await File(chemin).readAsBytes();
        final ex = xl.Excel.decodeBytes(octets);
        if (ex.tables.isEmpty) throw Exception('classeur vide');
        setState(() {
          nom = f.name;
          mode = 'excel';
          classeur = ex;
        });
        chargerFeuille(ex.tables.keys.first);
      } catch (e) {
        message('Impossible de lire ce fichier Excel.');
      }
    } else if (textExt.contains(ext)) {
      final octets = await File(chemin).readAsBytes();
      setState(() {
        nom = f.name;
        mode = 'texte';
        ctrl.text = utf8.decode(octets, allowMalformed: true);
      });
    } else {
      await OpenFilex.open(chemin);
    }
  }

  void chargerFeuille(String n) {
    final s = classeur!.tables[n]!;
    setState(() {
      feuille = n;
      lignes = s.maxRows < 10 ? 10 : s.maxRows;
      colonnes = s.maxColumns < 5 ? 5 : s.maxColumns;
    });
  }

  String texte(xl.CellValue? v) {
    if (v == null) return '';
    if (v is xl.TextCellValue) return v.value.toString();
    return v.toString();
  }

  Future<void> modifierCellule(int r, int c) async {
    final sheet = classeur!.tables[feuille]!;
    final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
    final champ = TextEditingController(text: texte(cell.value));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cellule ${lettre(c)}${r + 1}'),
        content: TextField(
          controller: champ,
          autofocus: true,
          maxLines: null,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, champ.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (res == null) return;
    setState(() {
      if (res.isEmpty) {
        cell.value = null;
      } else if (int.tryParse(res) != null) {
        cell.value = xl.IntCellValue(int.parse(res));
      } else if (double.tryParse(res.replaceAll(',', '.')) != null) {
        cell.value = xl.DoubleCellValue(double.parse(res.replaceAll(',', '.')));
      } else {
        cell.value = xl.TextCellValue(res);
      }
    });
  }

  Future<void> enregistrer() async {
    Uint8List octets;
    String? sortie = nom;
    String ext = 'txt';
    if (mode == 'excel') {
      final b = classeur!.encode();
      if (b == null) {
        message('Échec de l’enregistrement.');
        return;
      }
      octets = Uint8List.fromList(b);
      ext = 'xlsx';
    } else {
      octets = Uint8List.fromList(utf8.encode(ctrl.text));
    }
    final res = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer le fichier',
      fileName: sortie,
      bytes: octets,
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (res != null) message('Fichier enregistré');
  }

  Widget cellule(String t, double w, {bool entete = false, VoidCallback? tap}) {
    return InkWell(
      onTap: tap,
      child: Container(
        width: w,
        height: 42,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: entete ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
          border: Border.all(color: Colors.grey.shade500, width: 0.5),
        ),
        child: Text(t,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: entete ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget grille() {
    final sheet = classeur!.tables[feuille]!;
    const larg = 110.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 44 + colonnes * larg,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 90),
          itemCount: lignes + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Row(children: [
                cellule('', 44, entete: true),
                for (var c = 0; c < colonnes; c++)
                  cellule(lettre(c), larg, entete: true),
              ]);
            }
            final r = i - 1;
            return Row(children: [
              cellule('$i', 44, entete: true),
              for (var c = 0; c < colonnes; c++)
                cellule(
                  texte(sheet
                      .cell(xl.CellIndex.indexByColumnRow(
                          columnIndex: c, rowIndex: r))
                      .value),
                  larg,
                  tap: () => modifierCellule(r, c),
                ),
            ]);
          },
        ),
      ),
    );
  }

  Widget corps() {
    if (mode == 'excel') {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final n in classeur!.tables.keys)
                ChoiceChip(
                  label: Text(n),
                  selected: n == feuille,
                  onSelected: (_) => chargerFeuille(n),
                ),
              TextButton.icon(
                onPressed: () => setState(() => lignes++),
                icon: const Icon(Icons.add),
                label: const Text('Ligne'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => colonnes++),
                icon: const Icon(Icons.add),
                label: const Text('Colonne'),
              ),
            ],
          ),
        ),
        Expanded(child: grille()),
      ]);
    }
    if (mode == 'texte') {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: ctrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      );
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Appuie sur « Ouvrir un fichier » pour commencer.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(nom ?? 'Mon Appli', overflow: TextOverflow.ellipsis),
        actions: [
          if (nom != null)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Enregistrer',
              onPressed: enregistrer,
            ),
        ],
      ),
      body: corps(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: ouvrir,
        icon: const Icon(Icons.folder_open),
        label: const Text('Ouvrir un fichier'),
      ),
    );
  }
}
