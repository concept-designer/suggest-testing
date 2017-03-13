#Обёртка для работы с API сервиса подсказок от карты yandex.ru
package YandexAPI;
{
  use strict;
  use utf8;
  use LWP::UserAgent;
  use JSON;
  use Encode;
  
  #Отображение типов регионов, используемых в тестах, на типы, используемые яндексом
  my %RegionTypes = 
  (
    "обл" => [ "область" ],
    "Респ" => [ "республика" ],
    "АО" => [ "автономный округ" ],
    "Аобл" => [ "автономная область" ],
    "г" => [ "город" ],
  );
  
  #Отображение типов городов, используемых в тестах, на типы, используемые яндексом
  my %CityTypes = 
  (
    "г" => [ "город" ],
  );
  
  #Отображение типов улиц, используемых в тестах, на типы, используемые яндексом
  my %StreetTypes =
  (
    "ул" => [ "улица" ],
    "пер" => [ "переулок" ],
    "пр" => [ "проезд" ],
    "пр-кт" => [ "проспект" ],
    "ш" => [ "шоссе" ],
    "пл" => [ "площадь" ],
  );

  #Конструирует объект
  sub new( $$ )
  {
    my ( $class, $Token ) = @_;
    
    my $self = 
    { 
      user_agent => LWP::UserAgent->new( agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0", timeout => 600, keep_alive => 10 )
    };

    bless( $self, $class );

    return $self;    
  }
  
  #Отсылает HTTP-запрос сервису для получения подсказок по заданному префиксу
  #Должен вернуть объектную обёртку поверх JSON-ответа
  sub RequestSuggestions( $$ )
  {
    my ( $self, $Prefix ) = @_;
    
    my $Response = $self->{ user_agent }->get( "http://suggest-maps.yandex.ru/suggest-geo?callback=&lang=ru-RU&highlight=0&fullpath=1&sep=1&search_type=all&part=Россия, $Prefix&" );
    
    my $Result = undef;
    
    if( defined($Response) && $Response->is_success() )
    {
      $Result = from_json( Encode::decode( "utf8", $Response->content ) );
      
      #Если сервис не вернул подсказки, возвращаем undef
      if( defined( $Result ) && !exists( $Result->[1] ) )
      {
        $Result = undef;
      }
    }
    
    return $Result;
  }
  
  #Ищет среди возвращённых сервисом подсказок целевую
  sub FindPrediction( $$$$$ )
  {
    my ( $self, $Test, $Suggestions, $Stage, $LimitTopN ) = @_;
    
    my $Result = "";
    
    foreach my $Value ( @{ $Suggestions->[1] } )
    {
      #Сравниваем подсказку с целевым результатом, если совпала, значит сервис сделал правильное предсказание
      if( $self->CompareTestWithSuggestion( $Test, $Value->[2], $Stage ) == 1 )
      {
        $Result = $Value->[2];
        last;
      }
      $LimitTopN --;
      last if( $LimitTopN == 0 );
    }
    
    return $Result;
  }
  
  #Сравнивает полученную от сервиса подсказку с целевым значением
  sub CompareTestWithSuggestion( $$$ )
  {
    my ( $self, $Test, $Value, $Stage ) = @_;
    
    my $RetVal = 0;
    
    #Дробим на подстроки значение, которое вернул Яндекс
    my @SubValues = split( ',', $Value );
    
    #Строки должны идти в следующем порядке: Россия, Владимирская область, Муром
    #Область может быть пропущена, если имеем дело с городом - центром региона
    #Другие примеры:
    #Россия, Республика Карелия, Сортавальское городское поселение, Сортавала
    #Россия, Республика Коми, городской округ Инта, город Инта
    #Россия, Республика Коми, район Сосногорск, Сосногорск 
    #Россия, Владимир, улица Асаткина
    #Россия, Москва
    if( scalar( @SubValues ) > 1 && $SubValues[0] eq "Россия" )
    {
      #Перебираем все варианты
      if( $Stage eq "city" )
      {
        #Россия, Регион, Городское поселение, Город
        if( scalar( @SubValues ) == 4 )
        {
          $RetVal = ( $self->CompareRegion( $Test, $SubValues[1] ) && 
                      $self->CompareCity( $Test, $SubValues[3] ) ? 1 : 0 );
        }
        #Россия, Регион, Город
        elsif( scalar( @SubValues ) == 3 )
        {
          $RetVal = ( $self->CompareRegion( $Test, $SubValues[1] ) && 
                      $self->CompareCity( $Test, $SubValues[2] ) ? 1 : 0 );
        }
        #Россия, Город
        elsif( scalar( @SubValues ) == 2 )
        {
          $RetVal = $self->CompareCity( $Test, $SubValues[1] );
        }
      }
      elsif( $Stage eq "street" )
      {
        #Россия, Регион, Городское поселение, Город, Улица
        if( scalar( @SubValues ) == 5 )
        {
          $RetVal = ( $self->CompareRegion( $Test, $SubValues[1] ) && 
                      $self->CompareCity( $Test, $SubValues[3] ) &&
                      $self->CompareStreet( $Test, $SubValues[4] ) ? 1 : 0 );
        }
        #Россия, Регион, Город, Улица
        elsif( scalar( @SubValues ) == 4 )
        {
          $RetVal = ( $self->CompareRegion( $Test, $SubValues[1] ) && 
                      $self->CompareCity( $Test, $SubValues[2] ) &&
                      $self->CompareStreet( $Test, $SubValues[3] ) ? 1 : 0 );
        }
        #Россия, Город, Улица
        elsif( scalar( @SubValues ) == 3 )
        {
          $RetVal = ( $self->CompareCity( $Test, $SubValues[1] ) &&
                      $self->CompareStreet( $Test, $SubValues[2] ) ? 1 : 0 );
        }
      }
    }
    
    return $RetVal;
  }
  
  #Заменяет в строке буквы Ё на Е, ё на е 
  sub DegradeAlpha( $ )
  {
    my ( $self, $Strings ) = @_;
    
    $Strings =~ s/Ё/Е/gs;
    $Strings =~ s/ё/е/gs;
    
    return $Strings;
  }
  
  #Удаляет из строки $Value заданные подстроки. Строка $Value передаётся по ссылке
  sub DeleteStrings( $$$ )
  {
    my ( $self, $Value, $Strings ) = @_;
    
    my $Found = 0;
    
    #удаляем буквы ё из сравниваемых строк
    $$Value = $self->DegradeAlpha( $$Value );
    
    #Удаляем все альтернативные названия 
    foreach my $String ( @$Strings )
    {
      $String = $self->DegradeAlpha( $String );
      $Found = 1 if( $$Value =~ s/\b\Q$String\E\b//gi );
    }
    
    return $Found;
  }
  
  #Удляет все слова второй строки из первой строки. Первая строка передаётся по ссылке
  sub DeleteByWords( $$$ )
  {
    my ( $self, $String1, $String2 ) = @_;
    
    #получам слова тестового названия
    my @Words = grep { length( $_ ) > 0 } split /\W/, $String2;
    
    #сортируем по убыванию их длин
    @Words = sort { length($b) <=> length($a) } @Words;
    
    return $self->DeleteStrings( $String1, \@Words );
  }
  
  #Сравнивает регион, полученный от сервиса с регионом целевого адреса
  sub CompareRegion( $$$ )
  {
    my ( $self, $Test, $Value ) = @_;
    
    my $TestValue = $Test->{reg};
    my $TestType = $Test->{reg_type};
    
    #Удаляем все альтернативные названия типа
    $self->DeleteStrings( \$Value, $RegionTypes{ $TestType } );
    
    #Удаляем все слова целевого названия из полученной подсказки
    my $Found = $self->DeleteByWords( \$Value, $TestValue );
    
    #Удаляем слова самого типа
    $self->DeleteByWords( \$Value, $TestType );
    
    #Удаляем знаки пунктуации и пробелы
    my @Words = grep { length( $_ ) > 0 } split /\W/, $Value;
  
    return ( $Found == 1 && scalar( @Words ) == 0 ? 1 : 0 );
  }
  
  #Сравнивает город, полученный от сервиса с городом целевого адреса
  sub CompareCity( $$$ )
  {
    my ( $self, $Test, $Value ) = @_;
    
    #Учитываем вариант, когда в тесте задан город-регион
    my $TestValue = $Test->{city};
    $TestValue = $Test->{reg} if( $TestValue eq "" );
    
    my $TestType = $Test->{city_type};
    $TestType = $Test->{reg_type} if( $TestType eq "" );
    
    #Удаляем все альтернативные названия типа
    $self->DeleteStrings( \$Value, $CityTypes{ $TestType } );
    
    #Удаляем все слова целевого названия из полученной подсказки
    my $Found = $self->DeleteByWords( \$Value, $TestValue );
    
    #Удаляем слова самого типа
    $self->DeleteByWords( \$Value, $TestType );
    
    #Удаляем знаки пунктуации и пробелы
    my @Words = grep { length( $_ ) > 0 } split /\W/, $Value;
  
    return ( $Found == 1 && scalar( @Words ) == 0 ? 1 : 0 );
  }
  
  #Сравнивает улицу, полученную от сервиса с улицей целевого адреса
  sub CompareStreet( $$$ )
  {
    my ( $self, $Test, $Value ) = @_;
    
    my $TestValue = $Test->{street};
    my $TestType = $Test->{street_type};
    
    #Удаляем все альтернативные названия типа
    $self->DeleteStrings( \$Value, $StreetTypes{ $TestType } );
    
    #Удаляем все слова целевого названия из полученной подсказки
    my $Found = $self->DeleteByWords( \$Value, $TestValue );
    
    #Удаляем слова самого типа
    $self->DeleteByWords( \$Value, $TestType );
    
    #Удаляем знаки пунктуации и пробелы
    my @Words = grep { length( $_ ) > 0 } split /\W/, $Value;
  
    return ( $Found == 1 && scalar( @Words ) == 0 ? 1 : 0 );
  }
}
1;