#!/usr/bin/env perl 

use v5.20;
use utf8;
use open qw(:std :utf8);
use strict;
use warnings;
use XML::LibXML;
use JSON;
use Path::Tiny;

#use Getopt::Long;
#GetOptions( "stdout|s" => \our $use_stdout, "out|o" => \our $out_filename )
#  or die "Usage: $0 [--stdout|-s] [--out|-o] <filename>\n";

#my $in_filename = 'biblio-export-csl.json';
#my $in_filename = 'Zotero/zotero-export-csl.json';
my $in_filename   = 'Zotero/test-ufal.json';
my $out_filename  = 'RIV21-MSM-11320___,R01.vav';
my $obdobi        = '2021';
my $autor_dodavky = "Pavel Straňák";
my $autor_tel     = "221 914 247";
my $autor_email   = 'stranak@ufal.mff.cuni.cz';
my $verze         = "01";
my $cislo_jednaci = 1;
my $id_vvi        = 90101;    # ID VVI LINDAT/CLARIAH-CZ 01.01.2019 - 31.12.2022
my $fallback_obor =
  "undefined";    # TODO add CUNI code for LINDAT default area (obor)
my $fallback_keyword = "Digital Humanities";

# Publications from a CSL JSON file
my $json      = JSON->new->allow_nonref;
my $all_of_it = path($in_filename)->slurp;    #efficient with Path::Tiny
my $zotero    = $json->decode($all_of_it);
say "Imported $#{$zotero} results.";          #debug

# RIV XML template – START
my $encoding = 'utf8';
my $doc      = XML::LibXML::Document->new( '1.0', $encoding );
my $root =
  $doc->createElementNS( "urn:CZ-RVV-IS-VaV-XML-NS:data-1.2.9", "dodavka" );
$doc->setDocumentElement($root);
$root->setAttribute( 'struktura', 'RIV21A' );

#zahlavi = rozsah + dodavatel
my $header = $doc->createElement('zahlavi');
$header = $root->appendChild($header);

# rozsah
my $rozsah = $doc->createElement('rozsah');
$rozsah = $header->appendChild($rozsah);
$rozsah->appendTextChild( 'informacni-oblast', 'RIV' );
$rozsah->appendTextChild( 'obdobi-sberu',      $obdobi );
my $predkladatel = $doc->createElement('predkladatel');
$predkladatel = $rozsah->appendChild($predkladatel);
my $subjekt = $doc->createElement('subjekt');
$subjekt = $predkladatel->appendChild($subjekt);
$subjekt->appendTextChild( 'druh', 'verejna-vysoka-skola' );
$subjekt->appendTextChild( 'ICO',  '00216208' );
my $uk = $doc->createElement('nazev');
$uk = $subjekt->appendChild($uk);
$uk->appendTextNode('Univerzita Karlova');
$uk->setAttribute( 'jazyk', '#ORIG' );
my $cu = $doc->createElement('nazev');
$cu = $subjekt->appendChild($cu);
$cu->appendTextNode('Charles University');
$cu->setAttribute( 'jazyk', 'eng' );
$subjekt->appendTextChild( 'nadrizena-organizacni-slozka-statu', 'MSM' );

my $org_unit = $doc->createElement('organizacni-jednotka');
$org_unit = $predkladatel->appendChild($org_unit);
$org_unit->appendTextChild( 'kod', '11320' );    # TODO: opsano z prikladu
my $mff = $doc->createElement('nazev');
$mff = $org_unit->appendChild($mff);
$mff->appendTextNode('Matematicko-fyzikální fakulta');
$mff->setAttribute( 'jazyk', '#ORIG' );
my $mff_en = $doc->createElement('nazev');
$mff_en = $org_unit->appendChild($mff_en);
$mff_en->appendTextNode('Faculty of Mathematics and Physics');
$mff_en->setAttribute( 'jazyk', 'eng' );

# dodavatel
my $dodavatel = $header->addNewChild( "", 'dodavatel' );
$dodavatel->addNewChild( '', 'subjekt' )->appendTextChild( 'kod', 'MSM' );
my $osoba =
  $dodavatel->addNewChild( '', 'pracovnik-povereny-pripravou-dodavky' )
  ->addNewChild( '', 'osoba' );
$osoba->appendTextChild( 'cele-jmeno', $autor_dodavky );
my $kontakt = $osoba->addNewChild( '', 'kontakt' );
my $tel     = $kontakt->addNewChild( '', 'telefonni-cislo' );
$tel->setAttribute( 'druh', 'telefon' );
$tel->appendText($autor_tel);
$kontakt->appendTextChild( 'emailova-adresa', "$autor_email" );

$header->appendTextChild( 'verze', "$verze" );
$header->addNewChild( '', 'pruvodka' )
  ->setAttribute( 'cislo-jednaci', "$cislo_jednaci" );

#obsah
my $content = $doc->createElement('obsah');
$content = $root->appendChild($content);
my $result_elem_name = "vysledek";

# RIV XML Template – END

#JSON attributes to RIV XML elements – mapping
my %name_mapped = (
    "language" => "jazyk",
    "type"     => "druh",
    "abstract" => "anotace",
    "title"    => "nazev",
    "author"   => "autor",
    "last"     => "prijmeni",
    "given"    => "jmeno",
    "URL"      => "odkaz",
    "DOI"      => "doi",
);

# loop over the imported results and output them
for my $res_idx ( 0 .. $#{$zotero} ) {
    my $lang   = 'eng';                                            #default
    my $result = $content->addNewChild( '', $result_elem_name );

    # fixed result attributes - template
    $result->setAttribute( 'identifikacni-kod', $zotero->[$res_idx]->{"id"} );
    $result->setAttribute( 'duvernost-udaju',   'verejne-pristupne' );
    $result->setAttribute( 'rok-uplatneni',     $obdobi );
    $result->setAttribute( 'druh', 'ostatni' );  #TODO implementovat dalsi druhy

    # klasifikace – at least the main area (obor) and one keyword required
    my $klasifikace = $result->addNewChild( '', 'klasifikace' );
    my $obor_node   = $klasifikace->addNewChild( '', 'obor' );
    $obor_node->setAttribute( 'postaveni', 'hlavni' );
    $obor_node->setAttribute( 'ciselnik',  'oblastiUK' )
      ;    # obor dle klasifikace UK
           # get "obor" (area) from CSL and set it
           # CSL JSON doesn't have an attribute for this. We store it in
           # 'note' (Zotero displays as 'Extra') line 'obor:value'
    my ( $obor, @keywords );

    if ( defined $zotero->[$res_idx]->{'note'} ) {
        my $note = $zotero->[$res_idx]->{'note'};

        #        say "\nNOTE:\n-----\n$note\n" if defined $note;
        $note =~ m/^\s*obor\s*:\s*(\N+)\s*$/sm;
        $obor = $1;
        $note =~ m/^\s*kw\s*:\s*(\N+)\s*$/sm;
        my $kw_string = $1;
        @keywords = split( /,\s*/, $kw_string ) if defined $kw_string;
    }
    if (@keywords) {
        for my $kw (@keywords) {
            my $keyword_node = $klasifikace->addNewChild( '', 'klicove-slovo' );
            $keyword_node->setAttribute( 'jazyk', 'eng' );  # must be in English
            $keyword_node->appendText($kw);
        }
    }
    else {    # a fallback keyword to make data valid RIV
        my $keyword_node = $klasifikace->addNewChild( '', 'klicove-slovo' );
        $keyword_node->setAttribute( 'jazyk', 'eng' );    # must be in English
        $keyword_node->appendText($fallback_keyword);
    }

    # a fallback area (obor) to make data valid RIV
    $obor = $fallback_obor if not defined $obor;
    $obor_node->appendText($obor);

    # navaznosti - support of the LRI (why we are doing all of this)
    my $navaznosti = $result->addNewChild( '', 'navaznosti' );
    my $navaznost  = $navaznosti->addNewChild( '', 'navaznost' );
    $navaznost->setAttribute( 'druh-vztahu', 'byl-dosazen-pri-reseni' )
      ;    # p. 28 XML docs
    my $vvi = $navaznost->addNewChild( '', 'vvi' );
    $vvi->setAttribute( 'identifikacni-kod', $id_vvi );

    # simple text nodes unique per result
    for my $name (qw(language title abstract URL DOI)) {
        if ( defined $zotero->[$res_idx]->{$name} ) {
            $lang = $zotero->[$res_idx]->{"$name"} if $name eq 'language';

            # If language matches .*(Ee)ng.*, make it 'eng'. Even Bengali.
            $lang = ( $lang =~ /eng/i ) ? 'eng' : $lang;
            my $node = $result->addNewChild( '', $name_mapped{"$name"} );
            $node->appendText( $zotero->[$res_idx]->{$name} );
            $node->setAttribute( 'jazyk', $lang )
              if $name eq 'title' or $name eq 'abstract';
        }
    }

    # complex nodes

    # authors
    #    my $authors_node = $doc->createElement('autori');
    my $authors_node = $result->addNewChild( '', 'autori' );
    my $pocet_autoru;

    # loop over all authors
    for my $auth_idx ( 0 .. $#{ $zotero->[$res_idx]->{"author"} } ) {

        # get the author
        $pocet_autoru += 1;
        my $author_last =
          $zotero->[$res_idx]->{"author"}->[$auth_idx]->{"family"};
        my $author_given =
          $zotero->[$res_idx]->{"author"}->[$auth_idx]->{"given"};

        # set the author
        my $authornode =
          $authors_node->addNewChild( '', $name_mapped{'author'} );
        $authornode->setAttribute( 'je-domaci', 'false' );
        $authornode->appendTextChild( $name_mapped{'given'}, $author_given );
        $authornode->appendTextChild( $name_mapped{'last'},  $author_last );
    }
    $authors_node->setAttribute( 'pocet-celkem',   $pocet_autoru );
    $authors_node->setAttribute( 'pocet-domacich', '0' );
}

#TODO klasifikace, navaznosti, spravna ID zaznamu

#$state = $doc->toFile($filename, $format);

#if ($use_stdout) {
#    $doc->toFH( \*STDOUT );
#}
#else {
#$doc->setCompression('6');
#$doc->toFile( $out_filename, 0 );
$doc->toFile( $out_filename, 2 );

#}
