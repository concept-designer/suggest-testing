#Здесь представлен класс, в рамках которого реализован единый для всех сервисов сценарий тестирования
package TestWorker;
{
  use strict;
  use warnings;
  use utf8;
  use JSON;
  use Encode;
  use POSIX;
  use Time::HiRes;
  use TestStorage;
  
  #Кол-во миллисекунд, которые тратит медленный пользователь "тихоход" на ввод одной буквы
  #Константа используется при финальных расчётах формулы полезности
  my $UserTime_Slow = 1000;
  
  #Кол-во миллисекунд, которые тратит средний пользователь "середнячок" на ввод одной буквы
  #Константа используется при финальных расчётах формулы полезности
  my $UserTime_Medium = 600;
  
  #Кол-во миллисекунд, которые тратит быстрый пользователь "торопыжка" на ввод одной буквы
  #Константа используется при финальных расчётах формулы полезности
  my $UserTime_Fast = 300;
  
  #Коэффициент, определяющий сколько времени пользователь тратит на выбор предложенной подсказки
  #В статье для Хабра данный коэффициент обозначен заглавной латинской буквой C
  #Итоговое время определяется для каждого класса пользователя как 
  # $SelectSuggestionTimeCost * $UserTime_Slow 
  # $SelectSuggestionTimeCost * $UserTime_Medium 
  # $SelectSuggestionTimeCost * $UserTime_Fast 
  my $SelectSuggestionTimeCost = 3;
  
  #Конструирует объект, в качестве параметра получает 
  # - TestFilePath - путь к файлу с тестом
  # - ServiceAPIClass - имя класса-обёртки для API тестируемого сервиса, например, GoogleAPI
  # - LimitTopN - кол-во топовых подсказок выдачи сервиса, среди которых будем искать ожидаемый адрес
  sub new( $$$$$ )
  {
    my ( $class, $TestFilePath, $ServiceAPIClass, $LimitTopN, $Token ) = @_;
    
    #Имя файла с базой, куда сохраним результат тесирования
    my $StorageFileName = $TestFilePath;
    $StorageFileName =~ s/\.json$/_$ServiceAPIClass.sqlite/;
    
    my $self = 
    { 
      #список тестовых адресов
      tests => [],
      
      limit => $LimitTopN
    };

    bless( $self, $class );
    
    #API сервиса, который будем тестировать
    $self->{api} = new $ServiceAPIClass( $Token );
    
    #Здесь будем сохранять запросы и ответы, полученные от сервиса
    $self->{storage} = new TestStorage( $StorageFileName );
    
    #Читаем все тесты одним махом
    open( my $File, "<:utf8", $TestFilePath ) or die "Could not open file with tests.";
    my $TestJSON = do { local $/ = undef; <$File>; };
    close( $File );
    
    #Парсим JSON-текст с тестами
    $self->{tests} = from_json( $TestJSON );
    
    return $self;
  }
  
  #Главный метод тестера.
  #Обходит все тестовые адреса, генерирует для каждого адреса запросы подсказок, сохраняет результаты в БД
  sub Run( $ )
  {
    my ( $self ) = @_;
    
    my $Counter = 0;
    my $Skipped = 0;
    foreach my $Test ( @{ $self->{tests} } )
    {
      #Обрабатываем, только если по данному тесту нет результатов
      if( !$self->{storage}->IsFinished( $Test->{id} ) )
      {
        print "Prcoessing test ID: ", $Test->{id}, "\n";
        
        $self->{storage}->BeginTest();
        
        #Удаляем всё, что накоплено по данному тесту
        $self->{storage}->DeleteTest( $Test->{id} );
        
        #Генерируем префиксы для города
        my $Cities = $self->BuildCityPrefixes( $Test );
        
        #Запрашиваем подсказки для каждого префикса, пока не получим ожидаемый город
        my $CityPrediction = $self->ProcessPrefixes( $Test, $Cities, "city" );
        
        #Теперь делаем тоже самое с улицей, префиксы для улицы получаем с учётом полученной подсказки по городу
        if( defined $CityPrediction && $CityPrediction ne "" )
        {
          my $Streets = $self->BuildStreetPrefixes( $CityPrediction, $Test );
          
          $self->ProcessPrefixes( $Test, $Streets, "street" );
        }
        
        $self->{storage}->CommitTest();
        
        #Если сервис вернул некорректный ответ, выводим предупреждение
        if( !defined $CityPrediction )
        {
          print "Have no city prediction\n";
          $Skipped ++;
        }
        
        $Counter ++;
        print "Prcoessed tests: $Counter\n";
      }
    }
    
    print "Skipped tests $Skipped\n";
  }
  
  #Возвращает массив префиксов для названия города
  # - Test - исходный тест, откуда берёт название города
  sub BuildCityPrefixes( $$ )
  {
    my ( $self, $Test ) = @_;
    
    my $Result = [];
    
    #Если нет кастомизированного метода для генерации префиксов у самого сервиса, 
    #то генерируем префиксы стандартно
    if( !$self->{api}->can( "BuildCityPrefixes" ) )
    {
      my $String = $Test->{city};
      
      #Имеем дело с городом федерального значения
      $String = $Test->{reg} if( $String eq "" && $Test->{reg_type} eq "г" );
    
      my $Prefix = "";
      foreach my $Letter ( split( "", $String ) )
      {
        $Prefix .= $Letter;
        push @$Result, $Prefix;
      }
      
      #Добавляем пробел к последнему префиксу, чтобы сообщить, что это полное имя города
      push @$Result, $Prefix." ";
    }
    #Если у API есть кастомизированный метод, то вызываем его, т.к. API сервиса лучше знает, какие префиксы ему подходят
    else
    {
      $Result = $self->{api}->BuildCityPrefixes( $Test );
    }
    
    return $Result;
  }
  
  #Возвращает массив префиксов для названия улицы
  # - PredictedCity - правильно предложенный сервисом город в одной из предыдущих подсказок,
  #   он вставляется в начало каждого формируемого префикса улицы
  # - Test - исходный тест, откуда берёт название улицы
  sub BuildStreetPrefixes( $$$ )
  {
    my ( $self, $PredictedCity, $Test ) = @_;
    
    my $Result = [];
    
    #Если нет кастомизированного метода для генерации префиксов у самого сервиса, 
    #то генерируем префиксы стандартно
    if( !$self->{api}->can( "BuildStreetPrefixes" ) )
    {
      my $Prefix = $PredictedCity." ";
    
      foreach my $Letter ( split( "", $Test->{street} ) )
      {
        $Prefix .= $Letter;
        push @$Result, $Prefix;
      }
      
      #Добавляем пробел к последнему префиксу, чтобы сообщить, что это полное имя улицы
      push @$Result, $Prefix." ";
    }
    #Если у API есть кастомизированный метод, то вызываем его, т.к. API сервиса лучше знает, какие префиксы ему подходят
    else
    {
      $Result = $self->{api}->BuildStreetPrefixes( $PredictedCity, $Test );
    }
    
    return $Result;
  }
  
  #Для каждого префикса текущего тестового адреса отсылает сервису соответствующий запрос, в полученном от сервиса ответе ищет ожидаемый адрес.
  #Если в ответе сервиса целевой адрес не найден, то переходит к более длинному префиксу.
  #Все полученные от сервиса ответы сохраняет в БД хранилища.
  #Возвращает целевую подсказку, соответствующую какому-то префиксу данного тестового адреса.
  #Вернёт пустую строку, если ни один из префиксов не дал подсказки для желаемого адреса.
  #Вернёт undef, если сервис не вернул нормальный JSON-ответ.
  sub ProcessPrefixes( $$$$ )
  {
    my ( $self, $Test, $Prefixes, $Stage ) = @_;
    
    my $Prediction = "";
    
    my $PrefixLen = 1;
    
    #Прогоняем каждый префикс через сервис, пока не получим в ответе ожидаемую подсказку
    foreach my $Prefix ( @$Prefixes )
    {
      my @Time1 = Time::HiRes::gettimeofday();
      
      my $Suggestions = $self->{api}->RequestSuggestions( $Prefix );
      
      my @Time2 = Time::HiRes::gettimeofday();
      
      #Время выполнения запроса в миллисекундах
      my $Delta = ( $Time2[0] * 1000000 + $Time2[1] - ( $Time1[0] * 1000000 + $Time1[1] ) ) / 1000;
      
      if( defined $Suggestions )
      {
        #Проверяем, попал ли целевой результат в подсказки
        $Prediction = $self->{api}->FindPrediction( $Test, $Suggestions, $Stage, $self->{limit} );
        
        #Сохраняем данный результат в БД
        $self->{storage}->AddResponse( $Test, $Stage, $PrefixLen, $Prefix, $Suggestions, $Prediction, $Delta );
        
        #Если целевой результат попал в выдачу сервиса, то прекращаем
        last if( $Prediction ne "" );
      }
      else
      {
        #Сервис вернул некорректный ответ - заканчиваем тесты с ним
        $Prediction = undef;
        last;
      }
      
      $PrefixLen ++;
    }
    
    return $Prediction;
  }
  
  #Подсчитывает различные статистические характеристики по результату прохождения теста сервисом
  #В результате вернёт хэш со следующими ключами
  # reg_sum - Суммарное число букв в именах регионов, которые пользователю пришлось вручную ввести.
  #           Если пользователь получил правильную подсказку по городу, то считаем, что имя региона вводить не
  #           нужно было. Если подсказки по городу не было, то регион вводился целиком.
  #
  # city_sum - Суммарное число букв в именах городов, которые пользователю пришлось вручную ввести.
  #            Если по какому-то городу была получена правильная подсказка, то в этой сумме будет
  #            учтено только фактическое число букв префикса города, которые успел ввести пользователь, прежде,
  #            чем получил подсказку. Если правильной подсказки не было, то в этой сумме будет учтена
  #            длина полного имени города + длина типа города.
  #
  # street_sum - Аналогично city_sum, но для названия улиц.
  #
  # reg_overall - Суммарное число букв в полных названиях регионов, данное число просто характеризует тестовую
  #               выборку, оно не зависит от успешности прохождения тестов сервисом.
  #
  # city_overall - Аналог reg_overall, но для названий городов.
  #
  # street_overall - Аналог reg_overall, но для названий улиц.
  #
  # city_avg - Среднее число начальных букв, по которым сервис угадывает имя города.
  #            Данная статистика собирается только для тех тестов, по которым была получена
  #            правильная подсказка по имени города.
  #
  # street_avg - Аналог city_avg, но для улиц.
  #
  # city_successes - Кол-во адресов, в которых была получена правильная подсказка для города.
  #
  # street_successes - Кол-во адресов, в которых была получена правильная подсказка для улицы.
  sub CalcStatistics( $ )
  {
    my( $self ) = @_;
    
    my $Sum = { reg_sum => 0, city_sum => 0, street_sum => 0, 
                reg_overall => 0, city_overall => 0, street_overall => 0,
                city_avg => 0, street_avg => 0,
                city_successes => 0, street_successes => 0 };
    
    foreach my $Test ( @{ $self->{tests} } )
    {
      my $RegionFullLen = length( $Test->{reg}." ".$Test->{reg_type} );
      my $CityFullLen = length( $Test->{city}." ".$Test->{city_type} );
      my $StreetFullLen = length( $Test->{street}." ".$Test->{street_type} );
      
      #Число букв в имени региона, которые пришлось ввести пользователю при наборе данного адреса
      my $RegionInputLen = 0;
      
      #Кол-во букв, по которым была получена подсказка для города
      my $CityInputLen = $self->{storage}->GetPrefixLen( $Test->{id}, "city" );
      
      #Накапливаем статистику успешных подсказок по имени города
      if( $CityInputLen != 0 )
      {
        $Sum->{city_avg} += $CityInputLen; 
        $Sum->{city_successes} ++;
      }
      #Если подсказку по городу не получили, то считаем, что пользователь целиком ввёл имя города + ему пришлось вводить имя региона
      else
      {
        $CityInputLen = $CityFullLen;
        $RegionInputLen += $RegionFullLen;
      }
      
      #Кол-во букв, по которым была получена подсказка для улицы
      my $StreetInputLen = $self->{storage}->GetPrefixLen( $Test->{id}, "street" );
      
      #Накапливаем статистику успешных подсказок по имени улицы
      if( $StreetInputLen != 0 )
      {
        $Sum->{street_avg} += $StreetInputLen; 
        $Sum->{street_successes} ++;
      }
      #Если подсказку по улице не получили, то считаем, что пользователь целиком ввёл имя улицы
      else
      {
        $StreetInputLen = $StreetFullLen;
      }
      
      $Sum->{reg_sum} += $RegionInputLen;
      $Sum->{city_sum} += $CityInputLen;
      $Sum->{street_sum} += $StreetInputLen;
      
      $Sum->{reg_overall} += $RegionFullLen;
      $Sum->{city_overall} += $CityFullLen;
      $Sum->{street_overall} += $StreetFullLen;
    }
    
    #Усредняем накопленное число успешно введенных букв
    $Sum->{city_avg} = ( $Sum->{city_successes} > 0 ? $Sum->{city_avg} / $Sum->{city_successes} : 0 );
    $Sum->{street_avg} = ( $Sum->{street_successes} > 0 ? $Sum->{street_avg} / $Sum->{street_successes} : 0 );
    
    return $Sum;
  }
  
  #Подсчитывает все показатели результата тестирования и выводит их на экран
  sub CalcOverall( $ )
  {
     my( $self ) = @_;
     
     print "\n\n";
     
     #Собираем статистику по числу букв
     my $Stat = $self->CalcStatistics();
     
     #Среднее время отклика для подсказок для города и улицы
     print "Just interesting features:\n\n";
     print "city_avg(Ts) = ", $self->{storage}->GetAvgTime("city"), "\n";
     print "street_avg(Ts) = ", $self->{storage}->GetAvgTime("street"), "\n\n";
    
     #Среднее кол-во букв, которые пришлось ввести по всем тестам для городов и улиц
     print "city_avg(Nu) = ", $Stat->{city_avg}, "\n";
     print "street_avg(Nu) = ", $Stat->{street_avg}, "\n\n";
     
     #Суммарное кол-во букв, которые пришлось ввести по всем тестам для городов и улиц
     print "city(Nu) = ", $Stat->{city_sum}, "\n";
     print "street(Nu) = ", $Stat->{street_sum}, "\n";
     print "reg(Nu) = ", $Stat->{reg_sum}, "\n\n";
     
     #Суммарное число тестов, для которых город/улица были успешно угаданы
     print "city(S) = ", $Stat->{city_successes}, "\n";
     print "street(S) = ", $Stat->{street_successes}, "\n\n";
     
     #Суммарное время отклика для подсказок для города и улицы
     my $CitySumTime = $self->{storage}->GetSumTime("city");
     my $StreetSumTime = $self->{storage}->GetSumTime("street");
     
     print "city(Ts) = ", $CitySumTime, " (in minutes: ", $CitySumTime / (60*1000),")\n";
     print "street(Ts) = ", $StreetSumTime, " (in minutes: ", $StreetSumTime / (60*1000),")\n\n";
     
     #Суммарное кол-во букв в регионах, городах и улицах всех тестов
     print "city(No) = ", $Stat->{city_overall}, "\n";
     print "street(No) = ", $Stat->{street_overall}, "\n";
     print "reg(No) = ", $Stat->{reg_overall}, "\n\n";
     
     #Готовим данные для формулы полезности
     my $Nu = $Stat->{reg_sum} + $Stat->{city_sum} + $Stat->{street_sum};
     my $C = $SelectSuggestionTimeCost * ( $Stat->{city_successes} + $Stat->{street_successes} );
     my $No = $Stat->{reg_overall} + $Stat->{city_overall} + $Stat->{street_overall};
     my $Ts = $CitySumTime + $StreetSumTime;
     
     print "\nThese features participate in usefulness formula:\n\n";
     print "sum(Nu) = $Nu\n";
     print "sum(S) = ",$Stat->{city_successes} + $Stat->{street_successes},"\n";
     print "sum(No) = $No\n";
     print "sum(Ts) = $Ts", " (in minutes: ", $Ts / (60*1000),")\n\n";
     
     #Итоговое значение полезности для "тихохода", "середнячка" и "торопыжки"
     my $Usefulness_Slow = 1 - ( $Nu + $C )/$No - $Ts/( $No * $UserTime_Slow );
     my $Usefulness_Medium = 1 - ( $Nu + $C )/$No - $Ts/( $No * $UserTime_Medium );
     my $Usefulness_Fast = 1 - ( $Nu + $C )/$No - $Ts/( $No * $UserTime_Fast );
     
     print "U(Slow) = $Usefulness_Slow\n";
     print "U(Medium) = $Usefulness_Medium\n";
     print "U(Fast) = $Usefulness_Fast\n";
  }
};
1;