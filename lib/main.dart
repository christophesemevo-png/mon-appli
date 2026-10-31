import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:xml/xml.dart';

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

String nomColonne(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int indexColonne(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) {
      n = n * 26 + (u - 64);
    } else {
      break;
    }
  }
  return n - 1;
}

int indexLigne(String ref) {
  return int.parse(ref.replaceAll(RegExp(r'[A-Za-z]'), '')) - 1;
}

String texteNombre(double d) {
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

// ---------- Fichier zip (xlsx / docx) ----------

class Paquet {
  final Archive archive;
  final Map<String, XmlDocument> docs = {};
  final Set<String> modifies = {};
  Paquet(this.archive);

  XmlDocument doc(String chemin) {
    final deja = docs[chemin];
    if (deja != null) return deja;
    final f = archive.findFile(chemin);
    if (f == null) throw Exception('Partie manquante : $chemin');
    final texte =
        utf8.decode(f.content as List<int>).replaceFirst('\uFEFF', '');
    final d = XmlDocument.parse(texte);
    docs[chemin] = d;
    return d;
  }

  void touche(String chemin) => modifies.add(chemin);

  Uint8List octets() {
    final sortie = Archive();
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (modifies.contains(f.name) && docs[f.name] != null) {
        final b = utf8.encode(docs[f.name]!.toXmlString());
        sortie.addFile(ArchiveFile(f.name, b.length, b));
      } else {
        sortie.addFile(ArchiveFile(f.name, f.size, f.content));
      }
    }
    final z = ZipEncoder().encode(sortie);
    return Uint8List.fromList(z!);
  }
}

// ---------- Excel ----------

class Feuille {
  final String nom;
  final String chemin;
  Feuille(this.nom, this.chemin);
}

class Grille {
  final Map<String, String> vals = {};
  final Set<String> formules = {};
  int lignes = 0;
  int cols = 0;
}

class Xlsx {
  final Paquet p;
  final List<String> partages = [];
  final List<Feuille> feuilles = [];

  Xlsx(this.p) {
    if (p.archive.findFile('xl/sharedStrings.xml') != null) {
      for (final si in p.doc('xl/sharedStrings.xml').findAllElements('si')) {
        partages.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }
    final rels = <String, String>{};
    for (final rel
        in p.doc('xl/_rels/workbook.xml.rels').findAllElements('Relationship')) {
      rels[rel.getAttribute('Id') ?? ''] = rel.getAttribute('Target') ?? '';
    }
    for (final s in p.doc('xl/workbook.xml').findAllElements('sheet')) {
      final cible = rels[s.getAttribute('r:id') ?? ''] ?? '';
      if (cible.isEmpty) continue;
      final chemin = cible.startsWith('/') ? cible.substring(1) : 'xl/$cible';
      feuilles.add(Feuille(s.getAttribute('name') ?? 'Feuille', chemin));
    }
    if (feuilles.isEmpty) throw Exception('Aucune feuille trouvée');
  }

  String valeur(XmlElement c) {
    final t = c.getAttribute('t');
    if (t == 'inlineStr') {
      return c.findAllElements('t').map((e) => e.innerText).join();
    }
    final v = c.getElement('v');
    if (v == null) return '';
    if (t == 's') {
      final i = int.tryParse(v.innerText.trim());
      if (i != null && i >= 0 && i < partages.length) return partages[i];
      return '';
    }
    if (t == 'b') return v.innerText.trim() == '1' ? 'VRAI' : 'FAUX';
    var s = v.innerText;
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  Grille lire(Feuille f) {
    final g = Grille();
    for (final c in p.doc(f.chemin).findAllElements('c')) {
      final ref = c.getAttribute('r');
      if (ref == null) continue;
      final r = indexLigne(ref);
      final k = indexColonne(ref);
      if (c.getElement('f') != null) g.formules.add('$r,$k');
      final v = valeur(c);
      if (v.trim().isEmpty) continue;
      g.vals['$r,$k'] = v;
      if (r + 1 > g.lignes) g.lignes = r + 1;
      if (k + 1 > g.cols) g.cols = k + 1;
    }
    if (g.cols < 3) g.cols = 3;
    return g;
  }

  void ecrire(Feuille f, int r, int c, String texte) {
    final doc = p.doc(f.chemin);
    p.touche(f.chemin);
    final data = doc.findAllElements('sheetData').first;
    final ref = '${nomColonne(c)}${r + 1}';

    XmlElement? ligne;
    for (final row in data.childElements) {
      if (int.parse(row.getAttribute('r') ?? '0') == r + 1) {
        ligne = row;
        break;
      }
    }
    if (ligne == null) {
      ligne = XmlElement(XmlName('row'), [XmlAttribute(XmlName('r'), '${r + 1}')]);
      var pos = data.children.length;
      for (var i = 0; i < data.children.length; i++) {
        final n = data.children[i];
        if (n is XmlElement &&
            int.parse(n.getAttribute('r') ?? '0') > r + 1) {
          pos = i;
          break;
        }
      }
      data.children.insert(pos, ligne);
    }

    XmlElement? cel;
    for (final ce in ligne.childElements) {
      if (ce.getAttribute('r') == ref) {
        cel = ce;
        break;
      }
    }
    if (cel == null) {
      cel = XmlElement(XmlName('c'), [XmlAttribute(XmlName('r'), ref)]);
      var pos = ligne.children.length;
      for (var i = 0; i < ligne.children.length; i++) {
        final n = ligne.children[i];
        if (n is XmlElement && indexColonne(n.getAttribute('r') ?? 'A1') > c) {
          pos = i;
          break;
        }
      }
      ligne.children.insert(pos, cel);
    }

    cel.children.clear();
    cel.removeAttribute('t');
    final propre = texte.trim();
    if (propre.isEmpty) return;
    final nombre = double.tryParse(propre.replaceAll(',', '.').replaceAll(' ', ''));
    final zeroDevant = propre.length > 1 &&
        propre.startsWith('0') &&
        !propre.startsWith('0.') &&
        !propre.startsWith('0,');
    if (nombre != null && !zeroDevant) {
      cel.children.add(XmlElement(XmlName('v'), [], [XmlText(texteNombre(nombre))]));
    } else {
      cel.setAttribute('t', 'inlineStr');
      cel.children.add(XmlElement(XmlName('is'), [], [
        XmlElement(
            XmlName('t'), [XmlAttribute(XmlName('xml:space'), 'preserve')], [XmlText(texte)])
      ]));
    }
  }

  void recalculer(Feuille f) {
    final doc = p.doc(f.chemin);
    final nums = <String, double>{};
    final formules = <XmlElement>[];
    for (final c in doc.findAllElements('c')) {
      final ref = c.getAttribute('r');
      if (ref == null) continue;
      if (c.getElement('f') != null) {
        formules.add(c);
        continue;
      }
      final t = c.getAttribute('t');
      if (t != null && t != 'n') continue;
      final v = c.getElement('v');
      if (v == null) continue;
      final x = double.tryParse(v.innerText.trim());
      if (x != null) nums[ref] = x;
    }
    final re = RegExp(r'^SUM\(([A-Z]+)(\d+):([A-Z]+)(\d+)\)$');
    for (final c in formules) {
      final m = re.firstMatch(c.getElement('f')!.innerText.replaceAll(' ', ''));
      if (m == null) continue;
      final c1 = indexColonne(m.group(1)!);
      final c2 = indexColonne(m.group(3)!);
      final r1 = int.parse(m.group(2)!);
      final r2 = int.parse(m.group(4)!);
      var somme = 0.0;
      for (var r = r1; r <= r2; r++) {
        for (var k = c1; k <= c2; k++) {
          somme += nums['${nomColonne(k)}$r'] ?? 0;
        }
      }
      var v = c.getElement('v');
      if (v == null) {
        v = XmlElement(XmlName('v'));
        c.children.add(v);
      }
      v.children.clear();
      v.children.add(XmlText(texteNombre(somme)));
      c.removeAttribute('t');
    }
    p.touche(f.chemin);
  }

  void preparerSauvegarde() {
    final cp = p.doc('xl/workbook.xml').findAllElements('calcPr');
    if (cp.isNotEmpty) {
      cp.first.setAttribute('fullCalcOnLoad', '1');
      p.touche('xl/workbook.xml');
    }
  }
}

// ---------- Word ----------

class Docx {
  final Paquet p;
  late final XmlElement corps;

  Docx(this.p) {
    corps = p.doc('word/document.xml').findAllElements('w:body').first;
  }

  String texte(XmlElement para) =>
      para.findAllElements('w:t').map((e) => e.innerText).join();

  List<XmlElement> blocs() {
    return corps.childElements.where((e) {
      final n = e.name.qualified;
      if (n == 'w:tbl') return true;
      if (n == 'w:p') return texte(e).trim().isNotEmpty;
      return false;
    }).toList();
  }

  String texteCellule(XmlElement tc) {
    return tc
        .findElements('w:p')
        .map(texte)
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
  }

  void ecrireParagraphe(XmlElement para, String texte) {
    p.touche('word/document.xml');
    final ts = para.findAllElements('w:t').toList();
    if (ts.isEmpty) {
      if (texte.isEmpty) return;
      final run = XmlElement(XmlName.parse('w:r'), [], [
        XmlElement(XmlName.parse('w:t'),
            [XmlAttribute(XmlName.parse('xml:space'), 'preserve')], [XmlText(texte)])
      ]);
      para.children.add(run);
      return;
    }
    final premier = ts.first;
    premier.children.clear();
    premier.children.add(XmlText(texte));
    premier.setAttribute('xml:space', 'preserve');
    for (final t in ts.skip(1)) {
      t.children.clear();
    }
  }

  void ecrireCellule(XmlElement tc, String texte) {
    final ps = tc.findElements('w:p').toList();
    if (ps.isEmpty) return;
    final lignes = texte.split('\n');
    for (var i = 0; i < ps.length; i++) {
      String s;
      if (i >= lignes.length) {
        s = '';
      } else if (i == ps.length - 1) {
        s = lignes.sublist(i).join(' ');
      } else {
        s = lignes[i];
      }
      ecrireParagraphe(ps[i], s);
    }
  }
}

// ---------- Écran ----------

class Accueil extends StatefulWidget {
  const Accueil({super.key});

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  String? nom;
  Paquet? paquet;
  Xlsx? xlsx;
  Docx? docx;
  Feuille? feuille;
  Grille grille = Grille();

  void message(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void erreur(String titre, String detail) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre),
        content: SingleChildScrollView(child: SelectableText(detail)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<String?> demander(String titre, String initial) {
    final champ = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre),
        content: TextField(controller: champ, autofocus: true, maxLines: null),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, champ.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> ouvrir() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.single.path == null) return;
    final f = r.files.single;
    final chemin = f.path!;
    final ext = (f.extension ?? '').toLowerCase();
    if (ext == 'xlsx' || ext == 'docx') {
      try {
        final octets = await File(chemin).readAsBytes();
        final p = Paquet(ZipDecoder().decodeBytes(octets));
        Xlsx? x;
        Docx? d;
        Feuille? fe;
        Grille g = Grille();
        if (ext == 'xlsx') {
          x = Xlsx(p);
          fe = x.feuilles.first;
          g = x.lire(fe);
        } else {
          d = Docx(p);
        }
        setState(() {
          nom = f.name;
          paquet = p;
          xlsx = x;
          docx = d;
          feuille = fe;
          grille = g;
        });
      } catch (e, st) {
        final trace = st.toString();
        erreur('Ouverture impossible',
            '$e\n\n${trace.length > 500 ? trace.substring(0, 500) : trace}');
      }
    } else {
      await OpenFilex.open(chemin);
    }
  }

  void changerFeuille(Feuille fe) {
    setState(() {
      feuille = fe;
      grille = xlsx!.lire(fe);
    });
  }

  Future<void> modifierCase(int r, int c) async {
    if (grille.formules.contains('$r,$c')) {
      message('Cette case est un calcul automatique.');
      return;
    }
    final res = await demander(
        'Cellule ${nomColonne(c)}${r + 1}', grille.vals['$r,$c'] ?? '');
    if (res == null) return;
    xlsx!.ecrire(feuille!, r, c, res);
    xlsx!.recalculer(feuille!);
    setState(() => grille = xlsx!.lire(feuille!));
  }

  Future<void> modifierParagraphe(XmlElement para) async {
    final res = await demander('Modifier le texte', docx!.texte(para));
    if (res == null) return;
    docx!.ecrireParagraphe(para, res.replaceAll('\n', ' '));
    setState(() {});
  }

  Future<void> modifierCaseWord(XmlElement tc) async {
    final res = await demander('Modifier la case', docx!.texteCellule(tc));
    if (res == null) return;
    docx!.ecrireCellule(tc, res);
    setState(() {});
  }

  Future<void> enregistrer() async {
    try {
      if (xlsx != null) xlsx!.preparerSauvegarde();
      final octets = paquet!.octets();
      final res = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le fichier',
        fileName: nom,
        bytes: octets,
      );
      if (res != null) message('Fichier enregistré');
    } catch (e, st) {
      final trace = st.toString();
      erreur('Enregistrement impossible',
          '$e\n\n${trace.length > 500 ? trace.substring(0, 500) : trace}');
    }
  }

  Widget caseExcel(String t, double w,
      {bool entete = false, VoidCallback? tap}) {
    return InkWell(
      onTap: tap,
      child: Container(
        width: w,
        height: 42,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: entete
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
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

  Widget vueExcel() {
    const larg = 110.0;
    final lignes = grille.lignes + 2;
    final cols = grille.cols;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          children: [
            for (final fe in xlsx!.feuilles)
              ChoiceChip(
                label: Text(fe.nom.trim()),
                selected: fe == feuille,
                onSelected: (_) => changerFeuille(fe),
              ),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 44 + cols * larg,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: lignes + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Row(children: [
                    caseExcel('', 44, entete: true),
                    for (var c = 0; c < cols; c++)
                      caseExcel(nomColonne(c), larg, entete: true),
                  ]);
                }
                final r = i - 1;
                return Row(children: [
                  caseExcel('$i', 44, entete: true),
                  for (var c = 0; c < cols; c++)
                    caseExcel(grille.vals['$r,$c'] ?? '', larg,
                        tap: () => modifierCase(r, c)),
                ]);
              },
            ),
          ),
        ),
      ),
    ]);
  }

  Widget caseWord(XmlElement tc) {
    return InkWell(
      onTap: () => modifierCaseWord(tc),
      child: Container(
        width: 130,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade500, width: 0.5),
        ),
        child: Text(docx!.texteCellule(tc), maxLines: 5, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget vueWord() {
    final blocs = docx!.blocs();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
      itemCount: blocs.length,
      itemBuilder: (ctx, i) {
        final b = blocs[i];
        if (b.name.qualified == 'w:p') {
          return InkWell(
            onTap: () => modifierParagraphe(b),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(docx!.texte(b)),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              for (final tr in b.findElements('w:tr'))
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final tc in tr.findElements('w:tc')) caseWord(tc),
                    ],
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget corps() {
    if (xlsx != null) return vueExcel();
    if (docx != null) return vueWord();
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Appuie sur « Ouvrir un fichier » : Excel (.xlsx) ou Word (.docx).',
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
          if (paquet != null)
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
