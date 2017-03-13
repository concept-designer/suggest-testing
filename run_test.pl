#Скрипт выполняет тестирование полезности сервисов автодополнения
#Для запуска следует использовать следующий синтаксис
# run_test.pl <полный путь к JSON файлу с тестами> <имя API-пакета тестируемого сервиса> <ключ для работы через API>
# пример:  run_test.pl /home/user/suggest_test_full.json GoogleAPI ABSDEFG
use strict;
use utf8;
use JSON;
use Encode;
use POSIX;
use Time::HiRes;
use TestStorage;
use TestWorker;
use AhunterAPI;
use GoogleAPI;
use DadataAPI;
use Fias24API;
use KladrAPI;
use YandexAPI;

#Кол-во топовых подсказок, среди которых анализируется выдача сервиса в поисках целевого адреса
my $LimitTopN = 5;

#Первый аргумент содержит полный путь к файлу с тестами
my $TestFileName =  $ARGV[0];

#Второй аргумент содержит имя класса API-обёртки тестируемого сервиса
my $ServiceAPIClass = $ARGV[1];

#Третий аргумент - токен для работы с сервисом, для бесплатных сервисов не обязателен
my $Token = ( scalar(@ARGV) > 2 ? $ARGV[2] : "" );

print "Test file: $TestFileName\n";
print "Service API: $ServiceAPIClass\n";

if( $TestFileName ne "" && $ServiceAPIClass ne "" )
{
  print "Please wait for about 2 min while we initialize...\n";
  my $Worker = new TestWorker( $TestFileName, $ServiceAPIClass, $LimitTopN, $Token );

  print "Processing...\n";
  $Worker->Run();
  $Worker->CalcOverall();
}
else
{
  print "Wrong test file or service API.\n"
}


