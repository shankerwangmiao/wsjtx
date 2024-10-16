// -*- Mode: C++ -*-
//this file by w3sz
#ifndef QSYMESSAGECREATOR_H
#define QSYMESSAGECREATOR_H
#include <QWidget>
#include <QObject>

namespace Ui {
  class QSYMessageCreator;
}

class QSYMessageCreator
  : public QWidget
{
  Q_OBJECT

public:
  explicit QSYMessageCreator(QWidget * parent = 0);  
  ~QSYMessageCreator();
  
protected:
    void showEvent(QShowEvent *event) override {
        QWidget::showEvent(event); // Call the base class implementation        
        setup();
    }  
  
signals:
  void sendMessage(const QString &value);  
  
private:
  Ui::QSYMessageCreator *ui;
  QString getBand();
  QString getMode(QString band);
  
private slots:
void on_button1_clicked();
void setup();
};

#endif //QSYMESSAGECREATOR_H