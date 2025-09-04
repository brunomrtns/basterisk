#!/usr/bin/perl
#--------------------------info------------------------------
#Programa que usa a API do telein para fazer uma            -
#consulta usando um numero de celular e obtendo             -
#como resposta a operadora.                                 -
#cada servidor possibilita apenas seis consultas ip/dia     -
#esse programa usa os três servidores da telein,aumentando  -
#a quantidade de consultas para dezoito/dia.                -
#contato@rafaelmspc.cc                                      -
#http://www.rafaelmspc.cc                                   -
#------------------------------------------------------------
use LWP::UserAgent;
use v5.10;
use warnings;
use strict;
 
my ($num,$ua,$resp,$cont,$cdgvl,$cod,%tcod);
 
$num = $ARGV[0] ; chomp($num);
 %tcod =  (
    12 =>  "CTBC",
    14 =>  "Brasil Telecom",
    20 =>  "Vivo",
    21 =>  "Claro",
    31 =>  "Oi",
    24 =>  "Amazonia",
    37 =>  "Unicel",
    41 =>  "TIM",
    77 =>  "Nextel",
    43 =>  "SerComercio",
    81 =>  "Datora",
    98 =>  "Telefone Fixo",
    99 =>  "Nº nao encontrado",
    999 =>  "Chave invalida!",
    995 => "IP excedeu 6 consultas/hora nas ultimas 24 horas",
    990 => "IP na lista negra." ); 
 
 
for (1..3){
	$ua = LWP::UserAgent->new();
	$ua-> agent("Mozilla/5.0 (Windows; U; Windows NT 5.1; en; rv:1.9.0.4) Gecko/2008102920 Firefox/3.0.4");  
	$ua->timeout( 2 );
	$resp = $ua->get("http://consultanumero$_.telein.com.br/sistema/consulta_numero.php?chave=senhasite&numero=$num");
	$cod = substr($resp->decoded_content, 0,2);
	if ($cod =~ m/\d/){
		printf "$num,$tcod{$cod},$cod\n";
		exit
	}
}
