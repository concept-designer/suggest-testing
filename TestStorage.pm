#Здесь реализован интерфейс хранилища тестов.
#Результаты тестов сохраняются в sqlite базе, чтобы после теста выполнить все необходимые расчёты.
package TestStorage
{
  use strict;
  use utf8;
  use DBI;
  use JSON;
  
  #Открывает БД с тестами
  sub new( $$ )
  {
    my ( $class, $FileName ) = @_;
    
    my $self = 
    { 
      filename => $FileName,
      dbh => DBI->connect("dbi:SQLite:dbname=$FileName","",""),
    };

    bless( $self, $class );
    
    #Используем одну единственную таблицу, куда будут сохраняться ответы от тестируемого сервиса
    #Поля таблицы:
    # id - идентификатор теста из тестовой выборки
    # stage - содержит "city", если ответ получен на этапе ввода названия города, либо "street",
    #         если ответ получен на этапе ввода названия улицы          
    # len - кол-во начальных букв вводимого названия города или улицы, отправленных в качестве запроса сервису
    # prefix - запрос, отправленный сервису
    # res - сюда записывается правильная подсказка, полученная от сервиса, либо пустая строка, если сервис
    #       вернул подсказки, не соответствующие нашим ожиданиям
    # json - json-ответ от сервиса, нужен для отладки
    # time - время ожидания ответа от сервиса в миллисекундах
    $self->{dbh}->do( "CREATE TABLE IF NOT EXISTS tests ( id INTEGER,
                                                          stage TEXT,
                                                          len INTEGER,
                                                          prefix TEXT,
                                                          res TEXT,
                                                          json TEXT,
                                                          time INTEGER )" );
    
    $self->{dbh}->do( "CREATE INDEX IF NOT EXISTS test_id_index ON tests (id)" );

    
    $self->{get_prediction} = $self->{dbh}->prepare('SELECT res, len FROM tests WHERE id=? and stage=? and res !="" ');
    $self->{insert} = $self->{dbh}->prepare('INSERT INTO tests ( id, stage, len, prefix, res, json, time ) VALUES ( ?, ?, ?, ?, ?, ?, ? )');
    
    return $self;    
  }
  
  #Вернёт 1, если тест с заданным ID полностью выполнен
  #Выполненный тест имеет заполненные подсказки на этапе city и на этапе street
  sub IsFinished( $$ )
  {
    my( $self, $TestID ) = @_;
    
    my $Result = 0;
    
    $self->{get_prediction}->execute( $TestID, "city" );
    if( my $CityPrediction = $self->{get_prediction}->fetchrow_arrayref() )
    {
      $self->{get_prediction}->execute( $TestID, "street" );
      if( my $StreetPrediction = $self->{get_prediction}->fetchrow_arrayref() )
      {
        $Result = 1;
      }
    }
    
    return $Result;
  }
  
  #Возвращает кол-во букв, по которым была получена подсказка на заданном этапе ввода адреса
  sub GetPrefixLen( $$$ )
  {
    my( $self, $TestID, $Stage ) = @_;
    
    my $Result = 0;
    $self->{get_prediction}->execute(  $TestID, $Stage );
    
    if( my $Prediction = $self->{get_prediction }->fetchrow_arrayref() )
    {
      $Result = $Prediction->[1] if( defined $Prediction->[1] );
    }
    
    return $Result;
  }
  
  #Возваращает суммарное число успешно полученных подсказок на заданном этапе
  sub GetSumSuccessTests( $$ )
  {
    my( $self, $Stage ) = @_;
    
    my $Result = 0;
    
    my $Query = $self->{dbh}->prepare('SELECT count() FROM tests WHERE stage=? and res !="" ');
    $Query->execute( $Stage );
    if( my $Count = $Query->fetchrow_arrayref() )
    {
      $Result = $Count->[0] if( defined $Count->[0] );
    }
    
    return $Result;
  }
  
  #Возваращает среднее время отклика для заданного этапа
  sub GetAvgTime( $$ )
  {
    my( $self, $Stage ) = @_;
    
    my $Result = 0;
    
    my $Query = $self->{dbh}->prepare('SELECT avg(time) FROM tests WHERE stage=?');
    $Query->execute( $Stage );
    if( my $Time = $Query->fetchrow_arrayref() )
    {
      $Result = $Time->[0] if( defined $Time->[0] );
    }
    
    return $Result;
  }
  
  #Возваращает среднее время отклика для заданного этапа
  sub GetSumTime( $$ )
  {
    my( $self, $Stage ) = @_;
    
    my $Result = 0;
    
    my $Query = $self->{dbh}->prepare('SELECT sum(time) FROM tests WHERE stage=?');
    $Query->execute( $Stage );
    if( my $Time = $Query->fetchrow_arrayref() )
    {
      $Result = $Time->[0] if( defined $Time->[0] );
    }
    
    return $Result;
  }
  
  #Удаляет все записи, соответствующие заданному тесту
  sub DeleteTest( $$ )
  {
    my( $self, $TestID ) = @_;
    
    $self->{dbh}->do( "DELETE FROM tests WHERE id = $TestID" );
  }
  
  #Запускает транзакцию в БД
  sub BeginTest( $ )
  {
    my( $self ) = @_;
    
    $self->{dbh}->do( "BEGIN TRANSACTION" );
  }
  
  #Фиксирует все изменения в БД
  sub CommitTest( $ )
  {
    my( $self ) = @_;
    
    $self->{dbh}->do( "COMMIT TRANSACTION" );
  }
  
  #Добавляет результат, полученный от сервиса в БД
  sub AddResponse( $$$$$$$$ )
  {
    my( $self, $Test, $Stage, $PrefixLen, $Prefix, $Suggestions,  $Prediction, $Time ) = @_;
    
    my $JSONText = to_json( $Suggestions );
    
    $self->{insert}->execute( $Test->{id}, $Stage, $PrefixLen, $Prefix, $Prediction, $JSONText, $Time );
  }
};
1;